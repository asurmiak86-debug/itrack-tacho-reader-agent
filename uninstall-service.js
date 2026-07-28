/*
 * Usuwa usługę Windows "i-track Tacho Agent" zainstalowaną przez install-service.js.
 * Wymaga uruchomienia JAKO ADMINISTRATOR.
 */
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Service } from 'node-windows';

const __dirname = dirname(fileURLToPath(import.meta.url));

const svc = new Service({
  name: 'iTrackTachoAgent',
  script: join(__dirname, 'agent.js'),
});

svc.on('uninstall', () => {
  console.log('Usługa "i-track Tacho Agent" usunięta. Agent nie będzie już startować automatycznie z komputerem.');
});

svc.on('error', (err) => {
  console.error('Błąd usuwania usługi:', err);
});

svc.uninstall();
