/*
 * i-track Tacho DDD — agent czytnika kart (Etap 7, V1.1).
 *
 * UWAGA UCZCIWOŚCI: ten agent wykrywa czytnik i włożenie karty (ATR, model czytnika),
 * próbuje wybrać aplikację tachografu na karcie (SELECT po zweryfikowanym AID — patrz niżej)
 * i melduje się do i-track (heartbeat + samo-aktualizacja) — to już działa i jest gotowe do
 * testu z prawdziwym sprzętem. PEŁNY ODCZYT ZAWARTOŚCI (sekwencja READ BINARY per plik EF)
 * NIE jest jeszcze zaimplementowany — dokładne identyfikatory plików (FID) wymagają albo
 * pełnego tekstu specyfikacji (tabele w PDF, nie do wyciągnięcia automatycznie), albo
 * interaktywnego odkrycia na Twoim czytniku z prawdziwą kartą. Nie zgadujemy ich na sucho.
 *
 * AID aplikacji tachografu ('FF 54 41 43 48 4F') zweryfikowany wprost z tekstu rozporządzenia
 * UE (nie z pamięci) — SELECT tym AID jest bezpieczny (tylko nawigacja po systemie plików
 * karty, nie modyfikuje jej zawartości) i pozwoli potwierdzić, że karta w ogóle jest kartą
 * tachografu, zanim przejdziemy do odczytu konkretnych plików.
 *
 * Ten kod NIE był uruchamiany na fizycznym czytniku (serwer, na którym powstał, to Linux bez
 * podłączonego PC/SC) — sprawdzone jest tylko `node --check` (składnia). Realny test wymaga
 * Twojego komputera z zainstalowanym sterownikiem czytnika i usługą PC/SC (Windows: usługa
 * "Smart Card" musi być uruchomiona — zwykle jest domyślnie).
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { NFC } from 'nfc-pcsc';
import { config, validateConfig, hasAgentKey, STATUS_FILE, logEvent } from './config.js';
import { pairWithServer } from './pairing.js';

// Ten sam spakowany .exe obsługuje też diagnostykę (--diagnostic) — bez tego trzeba by
// dystrybuować drugi plik binarny tylko po to, żeby sprawdzić połączenie. Musi być PRZED
// resztą startu (a szczególnie przed `new NFC()`), żeby diagnostyka nie próbowała otwierać
// czytnika/karty równolegle z normalnie działającym agentem.
if (process.argv.includes('--diagnostic')) {
  await import('./diagnostic.js');
  process.exit(process.exitCode || 0);
}

/*
 * Test wirtualnej karty (--test-virtual-card) — symuluje pełny cykl "karta włożona → odczyt →
 * wyjęta" BEZ fizycznego czytnika/karty, wyłącznie żeby sprawdzić, że lokalny potok
 * status.json/events.jsonl/okno aplikacji w ogóle działa (np. w trakcie instalacji, zanim
 * dotrze prawdziwa karta). CELOWO nigdy nie woła sendHeartbeat/API — wysłanie fałszywego
 * "karta w czytniku" do panelu i-track byłoby złamaniem zasady uczciwych danych (administrator
 * widziałby nieprawdziwy stan prawdziwego klienta). Test jest w 100% lokalny.
 */
if (process.argv.includes('--test-virtual-card')) {
  const { STATUS_FILE: sf, EVENTS_FILE: ef, logEvent: le } = await import('./config.js');
  const { writeFileSync: wf } = await import('node:fs');
  console.log('=== TEST WIRTUALNEJ KARTY (symulacja lokalna — NIC nie wysyłane do i-track) ===');
  le('info', '[TEST WIRTUALNY] Symulowany czytnik podłączony');
  console.log('Symulowany czytnik podłączony.');
  await new Promise((r) => setTimeout(r, 500));
  le('info', '[TEST WIRTUALNY] Symulowana karta włożona (ATR testowy)');
  console.log('Symulowana karta włożona.');
  await new Promise((r) => setTimeout(r, 500));
  le('ok', '[TEST WIRTUALNY] Symulowany SELECT aplikacji tachografu: 9000 (OK)');
  console.log('Symulowany odczyt: OK (9000).');
  wf(sf, JSON.stringify({
    updatedAt: new Date().toISOString(), paired: false, serverReachable: false,
    readerPresent: true, readerModel: '(test wirtualny — nie prawdziwy czytnik)',
    cardPresent: true, cardStatus: 'virtual_test_ok', testMode: true
  }, null, 2));
  await new Promise((r) => setTimeout(r, 500));
  le('info', '[TEST WIRTUALNY] Symulowana karta wyjęta — test zakończony');
  console.log('Test zakończony. Wynik zapisany lokalnie (status.json, events.jsonl) — panel i-track NIE został poinformowany, to był test offline.');
  process.exit(0);
}

validateConfig();

const __dirname = dirname(fileURLToPath(import.meta.url));
const AGENT_VERSION = JSON.parse(readFileSync(join(__dirname, 'package.json'), 'utf8')).version;

// SELECT po AID aplikacji tachografu (ISO 7816-4): CLA=00 INS=A4(SELECT) P1=04(by name) P2=0C, Lc=6, AID.
const SELECT_TACHO_AID_APDU = Buffer.from([0x00, 0xa4, 0x04, 0x0c, 0x06, 0xff, 0x54, 0x41, 0x43, 0x48, 0x4f]);

async function apiFetch(path, opts = {}) {
  const res = await fetch(config.apiBase + '/api/agent/tacho' + path, {
    method: opts.method || 'GET',
    headers: { 'X-Agent-Key': config.agentKey, ...(opts.body ? { 'Content-Type': 'application/json' } : {}) },
    body: opts.body ? JSON.stringify(opts.body) : undefined
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`i-track API ${res.status}: ${text.slice(0, 200)}`);
  }
  return res.json().catch(() => ({}));
}

// Stan lokalny — pokazywany w logu agenta ORAZ wysyłany do i-track, żeby panel DDD widział
// to samo co operator patrzący na konsolę agenta (karta w czytniku + połączenie z serwerem).
const localState = { readerModel: null, cardPresent: false, cardStatus: null, lastHeartbeatOk: null, lastLatencyMs: null };

// status.json — czyta go ikona w zasobniku (tray.ps1), osobny proces bez dostępu do stdout
// agenta. Zapisywany po każdej zmianie stanu ORAZ co 5s (na wypadek gdyby tray wystartował
// później niż agent i przegapił pierwszy zapis).
function writeStatus() {
  const payload = {
    updatedAt: new Date().toISOString(),
    paired: hasAgentKey(),
    serverReachable: Boolean(localState.lastHeartbeatOk && (Date.now() - new Date(localState.lastHeartbeatOk).getTime()) < (config.heartbeatSeconds * 3 * 1000)),
    readerPresent: Boolean(currentReaderModel),
    readerModel: localState.readerModel,
    cardPresent: localState.cardPresent,
    cardStatus: localState.cardStatus,
    lastHeartbeatOk: localState.lastHeartbeatOk,
    lastLatencyMs: localState.lastLatencyMs,
    version: AGENT_VERSION,
    apiBase: config.apiBase
  };
  try { writeFileSync(STATUS_FILE, JSON.stringify(payload, null, 2)); } catch (_) {}
}

let lastHeartbeatWasOk = null; // null = jeszcze nie wiadomo; zapobiega spamowaniu dziennika tym samym zdarzeniem co 60s
async function sendHeartbeat(readerModel, cardPresent, cardStatus) {
  localState.readerModel = readerModel ?? localState.readerModel;
  if (typeof cardPresent === 'boolean') localState.cardPresent = cardPresent;
  if (cardStatus !== undefined) localState.cardStatus = cardStatus;
  const startedAt = Date.now();
  try {
    await apiFetch('/heartbeat', {
      method: 'POST',
      body: {
        readerModel: readerModel || null,
        cardPresent: typeof cardPresent === 'boolean' ? cardPresent : null,
        cardStatus: cardStatus !== undefined ? cardStatus : null
      }
    });
    localState.lastHeartbeatOk = new Date();
    localState.lastLatencyMs = Date.now() - startedAt;
    console.log(`[${new Date().toLocaleTimeString('pl-PL')}] heartbeat OK${readerModel ? ' (' + readerModel + ')' : ''}${typeof cardPresent === 'boolean' ? ' — karta: ' + (cardPresent ? 'W CZYTNIKU' : 'brak') : ''}`);
    if (lastHeartbeatWasOk === false) logEvent('ok', 'Połączenie z serwerem przywrócone');
    lastHeartbeatWasOk = true;
  } catch (error) {
    console.error(`[${new Date().toLocaleTimeString('pl-PL')}] heartbeat nieudany (brak połączenia z i-track?):`, error.message);
    if (lastHeartbeatWasOk !== false) logEvent('error', 'Utracono połączenie z serwerem: ' + error.message);
    lastHeartbeatWasOk = false;
  }
  writeStatus();
}

/*
 * Sprawdza wersję u i-track. Ta wersja agenta NIE aktualizuje się cicho sama (nadpisanie
 * własnego działającego pliku na Windows wymaga osobnego "launchera" — kolejny krok po
 * pierwszym teście). Na razie: jasny komunikat + link do pobrania nowej wersji.
 */
async function checkForUpdates() {
  try {
    const res = await fetch(config.apiBase + '/api/agent/tacho/version');
    if (!res.ok) return;
    const info = await res.json();
    if (info.ok && info.version && info.version !== AGENT_VERSION) {
      console.log('════════════════════════════════════════════════════════════');
      console.log(`Dostępna nowa wersja agenta: ${info.version} (masz ${AGENT_VERSION}).`);
      console.log(`Pobierz: ${info.downloadUrl}`);
      console.log('════════════════════════════════════════════════════════════');
    }
  } catch (error) {
    // Brak połączenia z i-track nie powinien zatrzymywać agenta — tylko pominięcie sprawdzenia.
  }
}

// Zarezerwowane pod pełny odczyt karty (przyszły krok) — już gotowe do użycia, gdy sekwencja
// APDU zostanie potwierdzona na realnym sprzęcie.
async function uploadDump(buffer, filename) {
  const form = new FormData();
  form.append('file', new Blob([buffer]), filename);
  const res = await fetch(config.apiBase + '/api/agent/tacho/upload', {
    method: 'POST',
    headers: { 'X-Agent-Key': config.agentKey },
    body: form
  });
  if (!res.ok) throw new Error(`Upload nieudany: HTTP ${res.status}`);
  return res.json();
}

let currentReaderModel = null;
let pairingInProgress = false;
let backgroundLoopsStarted = false;

// Uruchamiane albo od razu (jeśli AGENT_KEY/lokalny klucz już jest), albo dopiero po udanym
// parowaniu — PRZED sparowaniem nie ma sensu bić heartbeatem, bo i tak dostanie 401.
function startBackgroundLoops() {
  if (backgroundLoopsStarted) return;
  backgroundLoopsStarted = true;
  sendHeartbeat(currentReaderModel, false, null);
  checkForUpdates();
  setInterval(() => sendHeartbeat(currentReaderModel), config.heartbeatSeconds * 1000);
  setInterval(checkForUpdates, 6 * 60 * 60 * 1000); // co 6h
}

const nfc = new NFC();

nfc.on('reader', (reader) => {
  currentReaderModel = reader.reader.name;
  localState.readerModel = currentReaderModel;
  console.log(`Czytnik podłączony: ${currentReaderModel}`);
  logEvent('ok', 'Czytnik gotowy: ' + currentReaderModel);
  if (hasAgentKey()) sendHeartbeat(currentReaderModel);
  writeStatus();

  reader.on('card', async (card) => {
    console.log('Wykryto kartę. ATR:', card.atr ? card.atr.toString('hex') : '(brak ATR)');
    logEvent('info', 'Karta włożona (ATR: ' + (card.atr ? card.atr.toString('hex') : 'brak') + ')');

    // Zero wklejania u klienta: jeśli agent nie ma jeszcze klucza, PIERWSZA karta w czytniku
    // odpala parowanie z panelem i-track. Kolejne karty włożone w trakcie oczekiwania na
    // zatwierdzenie nie duplikują zgłoszenia (pairingInProgress).
    if (!hasAgentKey()) {
      if (pairingInProgress) { console.log('Parowanie z i-track w toku — czekaj na zatwierdzenie w panelu.'); return; }
      pairingInProgress = true;
      logEvent('info', 'Rozpoczęto parowanie z i-track');
      const ok = await pairWithServer({ readerModel: currentReaderModel, cardAtr: card.atr ? card.atr.toString('hex') : null });
      pairingInProgress = false;
      if (!ok) { console.log('Parowanie nieudane — wyjmij i włóż kartę ponownie, aby spróbować jeszcze raz.'); logEvent('error', 'Parowanie nieudane lub odrzucone'); return; }
      logEvent('ok', 'Sparowano z i-track pomyślnie');
      startBackgroundLoops();
    }

    let cardStatus = 'read_error';
    try {
      const response = await reader.transmit(SELECT_TACHO_AID_APDU, 256);
      const sw = response.slice(-2).toString('hex');
      if (sw === '9000') {
        console.log('SELECT aplikacji tachografu: OK (karta odpowiedziała poprawnie na wybranie aplikacji "TACHO"). To dobry znak — karta rozpoznaje się jako karta tachografu.');
        cardStatus = 'read_ok';
        logEvent('ok', 'Karta rozpoznana jako karta tachografu (SELECT 9000)');
      } else {
        console.log(`SELECT aplikacji tachografu: karta odpowiedziała kodem statusu ${sw} (nie 9000/OK). Może to nie być karta tachografu, albo card OS wymaga innych parametrów P1/P2 — prześlij ten kod do i-track.`);
        cardStatus = 'read_unexpected_sw';
        logEvent('warn', 'Karta odpowiedziała nieoczekiwanym kodem: ' + sw);
      }
      console.log('Surowa odpowiedź (hex):', response.toString('hex'));
    } catch (error) {
      console.log('SELECT aplikacji tachografu nieudany:', error.message, '— prześlij ten komunikat do i-track, to pomoże dopracować odczyt.');
      logEvent('error', 'Odczyt karty nieudany: ' + error.message);
    }
    console.log('Pełny odczyt zawartości karty (dane aktywności kierowcy) NIE jest jeszcze zaimplementowany w tej wersji agenta — wykrycie karty i rozpoznanie aplikacji tachografu już działa.');
    // Wysyłamy status OD RAZU (nie czekamy na kolejny cykliczny heartbeat) — panel DDD ma
    // widzieć "karta w czytniku" w ciągu sekund od włożenia, nie po heartbeatSeconds.
    localState.cardPresent = true; localState.cardStatus = cardStatus;
    if (hasAgentKey()) sendHeartbeat(currentReaderModel, true, cardStatus);
    else writeStatus();
  });

  reader.on('card.off', () => {
    console.log('Karta wyjęta.');
    logEvent('info', 'Karta wyjęta');
    localState.cardPresent = false; localState.cardStatus = null;
    if (hasAgentKey()) sendHeartbeat(currentReaderModel, false, null);
    else writeStatus();
  });

  reader.on('error', (err) => {
    console.error('Błąd czytnika:', err.message);
    logEvent('error', 'Błąd czytnika: ' + err.message);
    localState.cardStatus = 'reader_error';
    if (hasAgentKey()) sendHeartbeat(currentReaderModel, false, 'reader_error');
    else writeStatus();
  });

  reader.on('end', () => {
    console.log(`Czytnik odłączony: ${currentReaderModel}`);
    logEvent('warn', 'Czytnik odłączony');
    currentReaderModel = null;
    localState.readerModel = null; localState.cardPresent = false; localState.cardStatus = 'no_reader';
    if (hasAgentKey()) sendHeartbeat(null, false, 'no_reader');
    else writeStatus();
  });
});

nfc.on('error', (err) => {
  console.error('Błąd PC/SC (czy usługa Smart Card jest uruchomiona? czy sterownik czytnika jest zainstalowany?):', err.message);
  logEvent('error', 'Błąd PC/SC: ' + err.message);
  if (hasAgentKey()) sendHeartbeat(null, false, 'no_reader');
  else writeStatus();
});

console.log(`i-track Tacho — agent czytnika kart v${AGENT_VERSION} uruchomiony. Oczekiwanie na czytnik PC/SC...`);
logEvent('info', 'Usługa uruchomiona (wersja ' + AGENT_VERSION + ')');
if (!hasAgentKey()) console.log('Brak zapisanego klucza — agent czeka na pierwszą kartę w czytniku, żeby rozpocząć automatyczne parowanie z i-track (nic nie trzeba wklejać ręcznie).');
else startBackgroundLoops();
writeStatus();
// Niezależnie od stanu parowania — ikona w zasobniku ma widzieć status nawet przed sparowaniem.
setInterval(writeStatus, 5000);

process.on('SIGINT', () => { console.log('Zatrzymywanie agenta...'); process.exit(0); });
process.on('SIGTERM', () => { console.log('Zatrzymywanie agenta...'); process.exit(0); });
