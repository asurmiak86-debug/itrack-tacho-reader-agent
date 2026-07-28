/*
 * Parowanie bez wklejania niczego u klienta: przy pierwszej karcie w czytniku (jeśli agent
 * nie ma jeszcze zapisanego lokalnie klucza), sam generujemy losowy kod parowania, wysyłamy go
 * do i-track razem z ATR karty/nazwą komputera, i czekamy aż administrator zatwierdzi zgłoszenie
 * w panelu (Tacho DDD → Konto klienta → Oczekujące parowania). Po zatwierdzeniu serwer oddaje
 * właściwy klucz PRZY NAJBLIŻSZYM odpytaniu — zapisujemy go lokalnie i już nigdy nie pytamy o
 * ten sam kod ponownie (server sam czyści go po pierwszym odebraniu, patrz agentPairing.js).
 */
import crypto from 'node:crypto';
import os from 'node:os';
import { config, saveLocalKey } from './config.js';

const POLL_INTERVAL_MS = 5000;
const MAX_POLL_MS = 30 * 60 * 1000; // zgodne z TTL zgłoszenia po stronie serwera

function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }

export async function pairWithServer({ readerModel, cardAtr }) {
  const pairingCode = crypto.randomBytes(16).toString('hex');
  const hostname = os.hostname();
  console.log('════════════════════════════════════════════════════════════');
  console.log('Ten czytnik/komputer nie jest jeszcze sparowany z i-track.');
  console.log(`Nazwa komputera: ${hostname}${cardAtr ? ', ATR karty: ' + cardAtr : ''}`);
  console.log('Poproś administratora o zatwierdzenie w panelu i-track:');
  console.log('  Tacho DDD → Konto klienta → "Oczekujące parowania"');
  console.log('════════════════════════════════════════════════════════════');

  try {
    const res = await fetch(config.apiBase + '/api/agent/tacho/pair', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pairingCode, hostname, readerModel: readerModel || null, cardAtr: cardAtr || null })
    });
    if (!res.ok) { console.error('Zgłoszenie parowania nieudane: HTTP ' + res.status); return false; }
  } catch (error) {
    console.error('Zgłoszenie parowania nieudane (brak połączenia z i-track):', error.message);
    return false;
  }

  const deadline = Date.now() + MAX_POLL_MS;
  while (Date.now() < deadline) {
    await sleep(POLL_INTERVAL_MS);
    try {
      const res = await fetch(config.apiBase + '/api/agent/tacho/pair/' + pairingCode);
      if (!res.ok) continue;
      const info = await res.json();
      if (info.status === 'approved' && info.agentKey) {
        saveLocalKey(info.agentKey);
        console.log('Sparowano z i-track — klucz zapisany lokalnie. Agent działa normalnie od teraz.');
        return true;
      }
      if (info.status === 'denied') { console.error('Parowanie odrzucone przez administratora.'); return false; }
      if (info.status === 'expired') { console.error('Zgłoszenie parowania wygasło (30 min bez zatwierdzenia).'); return false; }
      // 'pending' — czekamy dalej, cicho (bez spamowania logu co 5s).
    } catch (error) {
      // Chwilowa utrata połączenia nie przerywa parowania — spróbujemy przy kolejnym ticku.
    }
  }
  console.error('Parowanie nie zostało zatwierdzone w ciągu 30 minut. Włóż kartę ponownie, aby spróbować jeszcze raz.');
  return false;
}
