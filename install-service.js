/*
 * Instaluje agenta jako usługę Windows ("i-track Tacho Agent") — uruchamia się AUTOMATYCZNIE
 * z rozruchem komputera (nie z zalogowaniem użytkownika), działa w tle bez okna konsoli,
 * i automatycznie restartuje się po awarii (node-windows domyślnie próbuje ponownie po crashu).
 *
 * Wymaga uruchomienia w PowerShell/cmd JAKO ADMINISTRATOR (rejestracja usługi Windows
 * wymaga uprawnień administracyjnych — to standardowe ograniczenie Windows, nie tej aplikacji).
 *
 * Użycie:  npm install  →  node install-service.js
 * Usunięcie usługi:      node uninstall-service.js
 */
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Service } from 'node-windows';

const __dirname = dirname(fileURLToPath(import.meta.url));

const svc = new Service({
  name: 'iTrackTachoAgent',
  description: 'i-track Tacho DDD — agent czytnika kart przedsiębiorstwa (łączy fizyczny czytnik PC/SC z panelem i-track).',
  script: join(__dirname, 'agent.js'),
  nodeOptions: [],
  // node-windows domyślnie: restart po awarii z rosnącym opóźnieniem — to jest pożądane
  // (agent ma działać ciągle, bez pilnowania przez operatora).
});

svc.on('install', () => {
  console.log('Usługa "i-track Tacho Agent" zainstalowana i uruchomiona.');
  console.log('Będzie teraz startować automatycznie z każdym uruchomieniem komputera — nie trzeba się logować.');
  svc.start();
});

svc.on('alreadyinstalled', () => {
  console.log('Usługa już jest zainstalowana. Użyj node uninstall-service.js, jeśli chcesz ją usunąć i zainstalować ponownie.');
});

svc.on('error', (err) => {
  console.error('Błąd instalacji usługi:', err);
  console.error('Czy ta konsola została uruchomiona JAKO ADMINISTRATOR? To najczęstsza przyczyna błędu.');
});

svc.install();
