/*
 * Diagnostyka połączenia — uruchamiana ręcznie (npm run diagnostic) albo z menu ikony w
 * zasobniku (tray.ps1 → "Test połączenia"). Sprawdza DNS, port 443, samo HTTPS i to, czy
 * endpoint parowania w ogóle odpowiada — bez zgadywania, każdy krok to realne zapytanie
 * sieciowe z jawnym wynikiem. Brak testu WebSocket celowo — ten agent łączy się zwykłym
 * REST/HTTPS (patrz pairing.js), nie ma tu żadnego kanału WS.
 */
import fs from 'node:fs';
import dns from 'node:dns/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { config, hasAgentKey, DATA_DIR, STATUS_FILE, LOCAL_KEY_FILE } from './config.js';

const results = [];
function result(name, ok, details = '') {
  results.push({ name, ok, details });
  console.log(`[${ok ? 'OK' : 'BŁĄD'}] ${name}${details ? ' — ' + details : ''}`);
}

function apiUrl() {
  try { return new URL(config.apiBase); } catch { return null; }
}

async function testDns() {
  const url = apiUrl();
  if (!url) return result('DNS', false, 'API_BASE ma niepoprawny format URL');
  try {
    const addresses = await dns.lookup(url.hostname, { all: true });
    result('DNS', addresses.length > 0, `${url.hostname} → ${addresses.map(a => a.address).join(', ')}`);
  } catch (error) { result('DNS', false, error.message); }
}

async function testTcp() {
  const url = apiUrl();
  if (!url) return;
  const port = Number(url.port || (url.protocol === 'https:' ? 443 : 80));
  await new Promise((resolve) => {
    const socket = net.createConnection({ host: url.hostname, port, timeout: 10000 });
    socket.once('connect', () => { result('TCP ' + port, true, `${url.hostname}:${port} osiągalny`); socket.destroy(); resolve(); });
    socket.once('timeout', () => { result('TCP ' + port, false, 'przekroczono czas — port zablokowany/niedostępny'); socket.destroy(); resolve(); });
    socket.once('error', (error) => { result('TCP ' + port, false, error.message); resolve(); });
  });
}

async function testHttps() {
  try {
    const response = await fetch(config.apiBase + '/api/agent/tacho/version', { signal: AbortSignal.timeout(15000) });
    const body = await response.json().catch(() => null);
    result('HTTPS + wersja agenta', response.ok, `HTTP ${response.status}${body?.version ? ', wersja serwera: ' + body.version : ''}`);
  } catch (error) { result('HTTPS + wersja agenta', false, error.cause?.message || error.message); }
}

async function testPairEndpoint() {
  try {
    // Celowo niepoprawny format kodu — oczekujemy 400 (VALIDATION), nie 404 (endpoint nie istnieje).
    const response = await fetch(config.apiBase + '/api/agent/tacho/pair', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ pairingCode: 'diagnostic-check' }),
      signal: AbortSignal.timeout(15000)
    });
    result('Endpoint parowania', response.status === 400, `HTTP ${response.status} (oczekiwano 400 — endpoint żyje, tylko odrzucił testowy kod)`);
  } catch (error) { result('Endpoint parowania', false, error.cause?.message || error.message); }
}

async function testHeartbeat() {
  if (!hasAgentKey()) return result('Heartbeat (klucz agenta)', true, 'pominięto — agent jeszcze niesparowany, to normalne przed pierwszym włożeniem karty');
  try {
    const response = await fetch(config.apiBase + '/api/agent/tacho/heartbeat', {
      method: 'POST', headers: { 'X-Agent-Key': config.agentKey, 'Content-Type': 'application/json' }, body: JSON.stringify({}),
      signal: AbortSignal.timeout(15000)
    });
    result('Heartbeat (klucz agenta)', response.ok, `HTTP ${response.status}` + (response.status === 401 ? ' — klucz odwołany lub nieprawidłowy, poproś administratora o ponowne sparowanie' : ''));
  } catch (error) { result('Heartbeat (klucz agenta)', false, error.cause?.message || error.message); }
}

function testFiles() {
  result('Katalog danych', fs.existsSync(DATA_DIR), DATA_DIR);
  result('Klucz agenta', true, hasAgentKey() ? 'agent sparowany (' + LOCAL_KEY_FILE + ')' : 'agent NIEsparowany — włóż kartę, żeby rozpocząć parowanie');
}

async function main() {
  console.log('\n==============================================');
  console.log(' i-track Tacho Agent — diagnostyka połączenia');
  console.log('==============================================');
  console.log(`Komputer: ${os.hostname()}`);
  console.log(`API: ${config.apiBase}\n`);
  testFiles();
  await testDns();
  await testTcp();
  await testHttps();
  await testPairEndpoint();
  await testHeartbeat();
  const reportPath = path.join(DATA_DIR, 'diagnostic-report.json');
  try { fs.writeFileSync(reportPath, JSON.stringify({ generatedAt: new Date().toISOString(), hostname: os.hostname(), apiBase: config.apiBase, results }, null, 2)); } catch (_) {}
  console.log(`\nRaport zapisany: ${reportPath}`);
  console.log(results.every((r) => r.ok) ? '\nWszystko OK.' : '\nSą problemy — sprawdź powyższe wpisy oznaczone [BŁĄD] i prześlij ten wynik do i-track.');
  process.exitCode = results.some((r) => !r.ok) ? 1 : 0;
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
