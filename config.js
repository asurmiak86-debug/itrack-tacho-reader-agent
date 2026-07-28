import 'dotenv/config';
import fs from 'node:fs';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
// Klucz zapisany TU lokalnie po sparowaniu (patrz pairing.js) — to jest miejsce "wklejenia
// tokenu" u klienta, tyle że robi to sam agent, automatycznie, po zatwierdzeniu w panelu
// i-track. Plik nie jest częścią repo (patrz .gitignore) — zawiera sekret per-instalacja.
export const LOCAL_KEY_FILE = join(__dirname, 'agent-key.local.json');

// status.json w %ProgramData% (nie obok agent.js) — czyta go ikona w zasobniku (tray.ps1),
// która NIE ma dostępu do konsoli agenta ani jego katalogu instalacyjnego z góry. ProgramData
// jest zapisywalne przez usługę (LocalSystem) i czytelne przez zalogowanego użytkownika.
export const DATA_DIR = join(process.env.PROGRAMDATA || join(os.homedir(), 'AppData', 'Local'), 'i-track', 'Tacho Agent');
export const STATUS_FILE = join(DATA_DIR, 'status.json');
// Dziennik zdarzeń (JSON Lines) — czyta go okno statusu aplikacji ("Ostatnie zdarzenia"/"Logi").
// Osobny od status.json (który trzyma tylko AKTUALNY stan) — to jest historia zmian w czasie.
export const EVENTS_FILE = join(DATA_DIR, 'events.jsonl');
const MAX_EVENTS = 500;
try { fs.mkdirSync(DATA_DIR, { recursive: true }); } catch (_) {}

export function logEvent(level, message) {
  const line = JSON.stringify({ at: new Date().toISOString(), level, message });
  try {
    fs.appendFileSync(EVENTS_FILE, line + '\n');
    // Przycinanie co jakiś czas, nie po każdym wpisie — appendFileSync jest tani, ale odczyt
    // całego pliku przy każdym zdarzeniu (żeby sprawdzić długość) już nie, więc robimy to
    // tylko z małym prawdopodobieństwem (~1 na 50 zdarzeń) zamiast liczyć linie za każdym razem.
    if (Math.random() < 0.02) {
      const lines = fs.readFileSync(EVENTS_FILE, 'utf8').split('\n').filter(Boolean);
      if (lines.length > MAX_EVENTS) fs.writeFileSync(EVENTS_FILE, lines.slice(-MAX_EVENTS).join('\n') + '\n');
    }
  } catch (_) {}
}

function readLocalKey() {
  try {
    const raw = fs.readFileSync(LOCAL_KEY_FILE, 'utf8');
    const data = JSON.parse(raw);
    return data.agentKey || null;
  } catch (error) {
    return null;
  }
}

export function saveLocalKey(agentKey) {
  fs.writeFileSync(LOCAL_KEY_FILE, JSON.stringify({ agentKey, savedAt: new Date().toISOString() }, null, 2), { mode: 0o600 });
  config.agentKey = agentKey;
}

// config NIE jest już zamrożone (Object.freeze) — agentKey może zostać uzupełniony w locie
// po zakończeniu parowania, bez restartu procesu (patrz saveLocalKey/pairing.js).
export const config = {
  apiBase: (process.env.API_BASE || 'https://ddd.i-track.pl').replace(/\/$/, ''),
  // Kolejność: ręczny AGENT_KEY w .env (stara ścieżka, wciąż wspierana dla zaawansowanych) ma
  // pierwszeństwo, jeśli ktoś świadomie go ustawił — inaczej: klucz zapisany lokalnie po
  // automatycznym sparowaniu — inaczej: pusty (agent wejdzie w tryb parowania).
  agentKey: process.env.AGENT_KEY || readLocalKey() || '',
  heartbeatSeconds: Math.max(10, Number(process.env.HEARTBEAT_SECONDS || 60))
};

export function hasAgentKey() {
  return Boolean(config.agentKey);
}

export function validateConfig() {
  // AGENT_KEY już NIE jest wymagany na starcie — brak klucza oznacza "wejdź w tryb
  // parowania po włożeniu karty" (patrz agent.js), nie błąd konfiguracji.
  if (!config.apiBase) {
    console.error('Brak lub niepoprawna konfiguracja agenta: API_BASE.');
    console.error('Skopiuj plik .env.example do .env i uzupełnij wartości.');
    process.exit(1);
  }
}
