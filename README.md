# i-track Tacho DDD — agent czytnika kart (Etap 7)

Ten folder to **osobna aplikacja**, którą instaluje się na komputerze w biurze klienta — NIE na serwerze i-track. Łączy fizyczny czytnik kart (np. ACS ACR39U) z systemem i-track.

## Stan tej wersji (V0.5) — uczciwie

- ✅ Wykrywanie podłączonego czytnika i włożenia karty (odczyt ATR).
- ✅ Próba wybrania aplikacji tachografu na karcie (`SELECT` po zweryfikowanym z tekstu rozporządzenia UE identyfikatorze `FF 54 41 43 48 4F`) — to bezpieczna, tylko-do-odczytu operacja nawigacji po systemie plików karty, nic nie zmienia. Wynik (kod statusu karty) pokazuje się w konsoli.
- ✅ Automatyczne parowanie bez wklejania klucza (patrz „Uruchomienie" niżej) + zgłaszanie się do i-track (heartbeat) — widoczne w panelu **Tacho DDD → Konto klienta**.
- ✅ Okno statusu + kolorowa ikona w zasobniku (`app.ps1`), dziennik zdarzeń, test połączenia, test wirtualnej karty — patrz sekcje niżej.
- ✅ Praca w tle jako usługa Windows (autostart, auto-restart po awarii).
- ✅ Sprawdzanie dostępności nowszej wersji (na razie: powiadomienie w konsoli + link do pobrania, bez cichej samo-podmiany plików — patrz sekcja „Aktualizacje" niżej).
- ❌ **Pełny odczyt zawartości karty kierowcy (dane aktywności — jazda/praca/odpoczynek) jeszcze nie działa.** SELECT aplikacji to dopiero pierwszy krok — odczyt konkretnych plików wymaga dokładnych identyfikatorów plików (FID), których nie udało się automatycznie wyciągnąć z oficjalnej specyfikacji (są w tabelach w PDF, nie w tekście). Ustalimy je **interaktywnie na podstawie kodu statusu z SELECT i realnych prób odczytu na Twoim sprzęcie** — to bezpieczniejsze niż zgadywanie na sucho.
- ❌ **Rozpoznawanie po numerze karty (nie po instalacji) po ponownej instalacji agenta jeszcze nie działa** — dziś parowanie jest przypisane do konkretnej instalacji (klucz zapisany lokalnie), nie do fizycznej karty. Prawdziwe „ta sama karta = automatyczna autoryzacja nawet po reinstalacji" wymaga odczytu numeru karty z samej karty — ta sama, dziś brakująca funkcja co punkt wyżej.

Ten kod nie był uruchamiany na fizycznym czytniku — powstał na serwerze Linux bez podłączonego PC/SC. Sprawdzona jest tylko poprawność składni (`npm run check`). Test na prawdziwym sprzęcie musisz wykonać Ty.

## Wymagania (Windows)

1. **Node.js 18+** — https://nodejs.org (wersja LTS).
2. **Sterownik czytnika ACS ACR39U** — zwykle instaluje się automatycznie przez Windows Update po podłączeniu USB; jeśli nie, sterownik jest na stronie producenta (Advanced Card Systems).
3. Usługa systemowa **"Smart Card"** musi być uruchomiona (Windows ma ją domyślnie włączoną — sprawdź w `services.msc`, jeśli czytnik nie jest wykrywany).
4. **Narzędzia budowania natywnych modułów Node** — pakiet `nfc-pcsc` wymaga kompilacji natywnego dodatku. Najprościej: zainstaluj `windows-build-tools` albo Visual Studio Build Tools (C++) przed `npm install`. Jeśli `npm install` zgłosi błąd kompilacji, to jest miejsce, gdzie to sprawdzić w pierwszej kolejności.

## Instalacja

```
npm install
copy .env.example .env
```

**Nic więcej nie trzeba wpisywać do `.env`.** `AGENT_KEY` zostaw puste — to jest teraz domyślna, "zero-config" ścieżka: agent sam się przedstawi i-track przy pierwszej karcie.

## Uruchomienie i automatyczne parowanie (bez wklejania czegokolwiek)

```
npm start
```

Przy pierwszym uruchomieniu bez klucza zobaczysz:
```
i-track Tacho — agent czytnika kart uruchomiony. Oczekiwanie na czytnik PC/SC...
Brak zapisanego klucza — agent czeka na pierwszą kartę w czytniku, żeby rozpocząć automatyczne parowanie z i-track (nic nie trzeba wklejać ręcznie).
Czytnik podłączony: ACS ACR39U ...
```

Włóż kartę (dowolną — parowanie nie wymaga jeszcze prawidłowej karty tachografu) — agent wyśle zgłoszenie do i-track i wypisze:
```
Ten czytnik/komputer nie jest jeszcze sparowany z i-track.
Nazwa komputera: BIURO-PC-01, ATR karty: 3b7f9600...
Poproś administratora o zatwierdzenie w panelu i-track:
  Tacho DDD → Konto klienta → "Oczekujące parowania"
```

Administrator w panelu i-track widzi to zgłoszenie (nazwa komputera, model czytnika, ATR karty, czas zgłoszenia), wybiera do którego klienta należy i klika „Zatwierdź". Agent w ciągu ~5 sekund odbierze klucz automatycznie, zapisze go lokalnie w pliku `agent-key.local.json` (obok `agent.js` — **nie commituj tego pliku, jest w `.gitignore`**) i od tej pory działa normalnie, bez żadnej interakcji — również po restarcie komputera (klucz zostaje zapisany).

Jeśli zatwierdzenie nie nastąpi w ciągu 30 minut, zgłoszenie wygasa — wystarczy wyjąć i włożyć kartę ponownie, żeby spróbować jeszcze raz (nowy kod parowania).

### Stara, ręczna ścieżka (opcjonalnie, dla zaawansowanych)

Jeśli z jakiegoś powodu wolisz ręcznie wygenerować klucz z góry (np. wystawiasz go razem z numerem karty przedsiębiorstwa w Tacho DDD → Karty firmy → „Zarejestruj kartę + wystaw klucz"), nadal możesz wkleić go do `.env` jako `AGENT_KEY` — ta wartość ma pierwszeństwo przed automatycznym parowaniem.

## Co zgłosić z powrotem

Po pierwszym teście z prawdziwym czytnikiem i kartą, prześlij:
- Czy `npm install` przeszedł bez błędów (jeśli nie — treść błędu).
- Czy czytnik został wykryty (log "Czytnik podłączony: ...").
- Czy włożenie karty zostało zauważone (log "Wykryto kartę. ATR: ...") — **prześlij ten ATR**.
- **Wynik SELECT aplikacji tachografu** — log zaczynający się od "SELECT aplikacji tachografu:" i linia "Surowa odpowiedź (hex):". To najważniejsza informacja do zbudowania pełnego odczytu — kod statusu (ostatnie 2 bajty, np. `9000` = sukces) mówi nam, czy trafiliśmy właściwą aplikację na karcie.

## Aktualizacje

Agent przy starcie i co 6h sprawdza w i-track, czy jest nowsza wersja — jeśli tak, wypisze w konsoli komunikat z linkiem do pobrania. **W tej wersji aktualizacja NIE jest cicha/automatyczna** (nadpisanie własnego działającego pliku `.exe` w trakcie działania nie jest bezpieczne bez osobnego "launchera" — to zaplanowany kolejny krok, po tym jak podstawowa wersja przejdzie pierwszy test). Na razie: pobierz nową paczkę z przycisku „Pobierz agenta (ZIP)" w panelu i-track i podmień pliki ręcznie.

## Budowanie pojedynczego pliku .exe (Windows) — bez wymogu instalowania Node.js u klienta

**To musisz zrobić Ty, na komputerze Windows** — natywny moduł czytnika kart trzeba skompilować na docelowej platformie (nie da się zbudować działającego pliku Windows z serwera Linux, na którym powstał ten kod).

```
npm install
npm install --save-dev @yao-pkg/pkg
npm run build:win
```

Gotowy plik pojawi się w `dist\itrack-tacho-agent.exe`. Ten plik możesz rozesłać dalej — **końcowy użytkownik NIE potrzebuje Node.js ani narzędzi budowania**, tylko sam plik `.exe` + plik `.env` obok niego (skopiowany z `.env.example`, z uzupełnionym `AGENT_KEY`).

**Uczciwie: ten proces budowania nie był przeze mnie wykonany ani przetestowany** (wymaga Windows) — konfiguracja w `package.json` (sekcja `"pkg"`) jest przygotowana zgodnie z dokumentacją narzędzia, ale natywne dodatki (`.node` pliki od `nfc-pcsc`) bywają kapryśne przy pakowaniu. Jeśli `npm run build:win` się nie powiedzie albo zbudowany `.exe` nie wykrywa czytnika (mimo że `npm start` go widzi), to pierwsza rzecz do zgłoszenia z powrotem — może wymagać drobnej korekty w `"assets"` w `package.json`.

## Pełny instalator Windows (`.exe` klikalny, z usługą i ikoną od razu)

Zamiast ręcznie budować `.exe` i potem ręcznie instalować usługę/skrót, jest gotowy instalator Inno Setup (`installer\itrack-tacho-agent.iss`) budowany automatycznie przez GitHub Actions (`.github\workflows\build-windows.yml`) — jeden plik `.exe`, który klient uruchamia i klika „Dalej".

**Zanim to zadziała, trzeba przygotować dwie rzeczy (raz, przy pierwszym buildzie):**
1. **`installer\nssm.exe`** (64-bit) — pobierz z https://nssm.cc/download i wrzuć do tego folderu. Używamy NSSM zamiast gołego `sc.exe create`, bo zwykły proces Node/pkg **nie implementuje protokołu Windows Service Control Manager** — `sc.exe create` wskazujące wprost na taki plik kończy się błędem „1053: usługa nie odpowiedziała na czas" (sprawdzone źródłowo, nie zgadywane). NSSM to sprawdzone, darmowe narzędzie robiące dokładnie to opakowanie poprawnie.
2. **To repozytorium musi być na GitHubie** (`git init`, remote, push) — workflow uruchamia się na runnerach GitHuba (potrzebny prawdziwy Windows do skompilowania natywnego modułu czytnika), nie da się tego zrobić lokalnie z tego serwera Linux. Dziś ten katalog **nie jest** repozytorium Git.

Po spełnieniu obu warunków: `git push` na branch `main` (albo ręczne uruchomienie z zakładki Actions) buduje `itrack-tacho-agent.exe`, pakuje go razem z oknem statusu, kolorowymi ikonami i NSSM w jeden instalator, i udostępnia jako artefakt do pobrania — bez potrzeby posiadania Windows do samego budowania (tylko do przygotowania `nssm.exe` raz).

**Uczciwie: ten workflow (jak cały pipeline `.exe`) nie był uruchomiony ani przetestowany** — konfiguracja jest przygotowana zgodnie z dokumentacją NSSM/Inno Setup/GitHub Actions, ale pierwszy realny build na Twoim repo pokaże, czy coś wymaga korekty.

## Praca w tle + autostart z komputerem (usługa Windows)

Docelowo agent ma działać bez otwartej konsoli i wstawać sam z każdym uruchomieniem komputera (nie z zalogowaniem użytkownika) — to daje `node-windows`, rejestrując agenta jako **prawdziwą usługę Windows**.

1. Najpierw sprawdź ręcznie przez `npm start` (sekcja „Uruchomienie" wyżej), że czytnik i karta działają — usługę instaluj dopiero, gdy to działa.
2. Otwórz PowerShell/cmd **jako Administrator** (prawy klik → „Uruchom jako administrator") — instalacja usługi Windows wymaga uprawnień administracyjnych, to standardowe ograniczenie systemu.
3. W folderze agenta:
   ```
   npm install
   npm run install-service
   ```
4. Powinno pojawić się `Usługa "i-track Tacho Agent" zainstalowana i uruchomiona.` Od teraz agent:
   - startuje automatycznie przy starcie komputera (widoczny w `services.msc` jako **iTrackTachoAgent**), zanim ktokolwiek się zaloguje,
   - działa w tle, bez okna konsoli,
   - **restartuje się sam po awarii** (crash agenta nie wymaga ręcznej interwencji).
5. Logi usługi trafiają do `daemon\` w folderze agenta (pliki `.log`/`.err.log` tworzone przez `node-windows`) — to tam szukać błędów, jeśli w panelu i-track agent przestanie się pojawiać jako aktywny.
6. Usunięcie usługi (np. przed odinstalowaniem albo aktualizacją na nowszą wersję agenta): `npm run uninstall-service` (też jako Administrator).

Alternatywa dla samej pracy w tle bez pełnej usługi systemowej (mniej solidne — wymaga zalogowanego użytkownika): [PM2](https://pm2.keymetrics.io/) z `pm2-windows-startup`. Zalecana ścieżka to jednak powyższa usługa Windows — działa niezależnie od tego, czy ktokolwiek jest zalogowany na komputerze.

## Okno statusu + ikona w zasobniku (`app.ps1`)

Osobny, lekki program (PowerShell + WinForms — nic dodatkowego do zainstalowania, to część Windows) pokazujący na żywo to, co widać w usłudze: połączenie z serwerem, czytnik, kartę i ostatnie zdarzenia. Działa niezależnie od usługi — tylko CZYTA jej pliki statusu, niczym nie steruje.

```
powershell -ExecutionPolicy Bypass -File app.ps1
```

(Instalator Windows robi to automatycznie — skrót w Autostarcie i w Menu Start.)

- **Ikona w zasobniku zmienia kolor** zależnie od stanu: szara (usługa zatrzymana), żółta (działa, ale niesparowany albo brak połączenia z serwerem), niebieska (połączono, brak czytnika/karty), zielona (karta w czytniku, gotowa), czerwona (błąd). Menu prawym klikiem: otwórz okno, test połączenia, otwórz logi, restart usługi, otwórz `ddd.i-track.pl`.
- **Okno statusu** (klik/dwuklik na ikonę): baner stanu, karta „Połączenie z serwerem" (adres API, ostatni kontakt, opóźnienie, przycisk „Test połączenia"), karta „Czytnik i karta" (model czytnika, status karty, przycisk „Testuj kartę (wirtualnie)"), lista ostatnich zdarzeń, zakładka „Logi" z pełną historią.
- **„Test połączenia"** uruchamia dokładnie to samo, co `--diagnostic` (patrz niżej), i pokazuje wynik w oknie dialogowym.
- **„Testuj kartę (wirtualnie)"** uruchamia symulację pełnego cyklu karta-włożona→odczyt→wyjęta **bez fizycznej karty** — przydatne np. w trakcie instalacji, zanim dotrze prawdziwa karta klienta, żeby sprawdzić, że cały lokalny potok (zapis statusu, dziennik zdarzeń, okno) działa. **Celowo w 100% lokalne — nic nie jest wysyłane do panelu i-track**, żeby nie zafałszować prawdziwego statusu klienta widocznego u administratora.

**Uczciwie: `app.ps1` nie był uruchamiany na prawdziwym Windows** (podobnie jak reszta tego kodu — powstał na serwerze Linux). Logika (odczyt `status.json`/`events.jsonl`, przełączanie widoków) jest przetestowana pośrednio przez testy `agent.js --test-virtual-card`/`--diagnostic`, które faktycznie zapisują pliki, jakie to okno czyta — ale samo renderowanie WinForms wymaga pierwszego testu na Twoim komputerze.

## Diagnostyka połączenia (`--diagnostic`)

```
npm run diagnostic
```
albo (spakowany `.exe`): `itrack-tacho-agent.exe --diagnostic`

Sprawdza po kolei: DNS, port TCP serwera, HTTPS + wersję serwera, czy endpoint parowania odpowiada, i (jeśli sparowany) czy klucz agenta wciąż działa. Wynik trafia też do `%ProgramData%\i-track\Tacho Agent\diagnostic-report.json` — prześlij ten plik do i-track, jeśli coś nie działa.

## Status karty i połączenia — widoczny w obie strony

- **Lokalnie (konsola/log agenta):** każdy heartbeat wypisuje aktualny stan, np. `heartbeat OK (ACS ACR39U ...) — karta: W CZYTNIKU`. Włożenie/wyjęcie karty albo błąd czytnika wysyła status do i-track **od razu** (nie czeka na kolejny cykliczny heartbeat) — więc panel i konsola pokazują to samo w ciągu kilku sekund.
- **Zdalnie (panel i-track → Tacho DDD → Karty firmy):** kolumna statusu przy każdej karcie/kluczu pokazuje `card_present` (karta w czytniku: tak/nie), `card_status` (`read_ok` = karta odpowiedziała jako karta tachografu / `read_unexpected_sw` = odpowiedziała, ale nieoczekiwanym kodem / `read_error`, `reader_error`, `no_reader`) oraz kiedy ten status ostatnio się zmienił.
- Jeśli agent straci połączenie z internetem, `last_seen_at` przestaje się aktualizować — panel odróżnia „karta w czytniku, ale agent offline" (stare `last_seen_at`) od „karta w czytniku i agent właśnie się zgłosił" (świeże `last_seen_at`).
