# Integracja z pttd (dyktowanie) dla Quickshella

Ten dokument jest samowystarczalny: opisuje wszystko, czego potrzeba, żeby w Quickshellu zrobić
widget dyktowania, bez znajomości repo `~/push-to-talk`.

## Zmiany względem poprzedniej wersji

Jeśli widget już implementuje poprzednią wersję tego dokumentu, nowe jest tylko:
- **tryb słowa kluczowego (wake)**: pole `wake` w `state` i odpowiedziach, komendy `wake_on`/`wake_off`/`wake_toggle`,
- **konfiguracja trybu wake przez socket**: komendy `wake_config`, `wake_phrases`, `wake_autostart`
  i zdarzenie `wake_config`,
- `subscribe` wysyła teraz **dwa** zdarzenia startowe: `state` i `wake_config`,
- nowa nazwa w zdarzeniu `command`: `wake`.

Wszystko jest addytywne: stary klient działa dalej, tylko nie pokazuje trybu wake.
Pełny opis: sekcja [Tryb słowa kluczowego (wake)](#tryb-słowa-kluczowego-wake).

## Co to jest

`pttd` to demon dyktowania na żywo (speech-to-text, polski). Po włączeniu słucha mikrofonu, tnie mowę
na fragmenty na pauzach, przepisuje je modelem whisper (usługa `whisper-server` na GPU) i wpisuje
tekst w aktywne okno przez emulację klawiatury. Działa jako usługa `systemd --user` (`pttd.service`).

Dyktowanie można włączyć na dwa sposoby, które działają obok siebie:
- **ręcznie**: `toggle`/`start`/`stop` (bind `SUPER+D`, przycisk w pasku),
- **głosem (tryb wake)**: po włączeniu trybu mikrofon słucha cały czas, a dyktowanie włącza się po
  wypowiedzeniu frazy startu (domyślnie „dyktuję”) i wyłącza po frazie stopu (domyślnie „full stop”).

Quickshell **nie** zajmuje się audio ani wpisywaniem tekstu. Jego rola:
1. pokazywać stan (serwer włączony/wyłączony/ładuje się, dyktowanie aktywne, użytkownik mówi,
   tryb wake czeka na frazę),
2. pokazywać jednolinijkowy podgląd rozpoznawanych słów na żywo,
3. pozwalać włączać/wyłączać dyktowanie, tryb wake i serwer z paska,
4. (opcjonalnie) panel ustawień trybu wake: frazy startu/stopu i autostart.

## Połączenie

- Socket Unix (stream): `$XDG_RUNTIME_DIR/ptt/ctl.sock` (zwykle `/run/user/1000/ptt/ctl.sock`).
- Protokół: **JSON-lines**, UTF-8. Każda wiadomość w obie strony to jeden obiekt JSON zakończony `\n`.
- Wystarczy **jedno długożyjące połączenie**: po wysłaniu `subscribe` przychodzą na nim zdarzenia,
  a przez to samo połączenie można dalej wysyłać komendy.
- Demona może nie być (nie działa, restartuje się). Wtedy połączenie się nie uda albo zostanie zamknięte.
  Widget powinien pokazać stan „niedostępny” i ponawiać połączenie co ~2 s.

W Quickshellu naturalnie pasuje `Socket` z `Quickshell.Io` z parserem dzielącym na linie
(`SplitParser`, separator `\n`), np. w singletonie `SttManager.qml`. Ścieżkę zbudować z
`Quickshell.env("XDG_RUNTIME_DIR") + "/ptt/ctl.sock"`. Po (ponownym) połączeniu od razu wysłać
`{"cmd":"subscribe"}`. Dokładne API (`write()`, `flush()`, `connected`) sprawdzić w używanej wersji Quickshella.

## Komendy (klient → demon)

Format: `{"cmd": "<nazwa>", ...argumenty}\n`. Komendy bez argumentów: samo `{"cmd": "<nazwa>"}`.

| komenda          | działanie |
|------------------|-----------|
| `subscribe`      | od teraz to połączenie dostaje zdarzenia; od razu przychodzą `state` i `wake_config` |
| `status`         | tylko odpowiedź ze stanem |
| `toggle`         | włącz/wyłącz dyktowanie |
| `start` / `stop` | włącz / wyłącz dyktowanie (idempotentne) |
| `hold_start` / `hold_stop` | push-to-talk (wciśnięcie / puszczenie klawisza); `hold_stop` nie wyłącza dyktowania włączonego przez `toggle`/`start` |
| `server_start`   | uruchom whisper-server (ładuje model do VRAM, kilka sekund) |
| `server_stop`    | zatrzymaj whisper-server (zwalnia ~4 GB VRAM); wyłącza też dyktowanie i tryb wake |
| `server_restart` | restart whisper-server (gdy coś nie działa) |
| `wake_on` / `wake_off` / `wake_toggle` | włącz / wyłącz / przełącz tryb słowa kluczowego (idempotentne) |
| `wake_config`    | odpowiedź z ustawieniami trybu wake (frazy, autostart) zamiast stanu |
| `wake_phrases`   | zmiana fraz; argumenty `kind`, `op`, `phrases` (niżej) |
| `wake_autostart` | tryb wake od startu demona; argument `on` (bool) |

`start`/`toggle`/`wake_on` przy wyłączonym serwerze same go uruchamiają; fragmenty mowy czekają, aż
serwer będzie gotowy.

Argumenty komend konfiguracyjnych trybu wake:
```json
{"cmd": "wake_phrases", "kind": "start", "op": "add", "phrases": ["zacznij pisać"]}
{"cmd": "wake_phrases", "kind": "stop", "op": "remove", "phrases": ["stop dyktowania"]}
{"cmd": "wake_phrases", "kind": "start", "op": "set", "phrases": ["dyktuję", "piszę"]}
{"cmd": "wake_autostart", "on": true}
```
- `kind`: `start` | `stop`; `op`: `set` (zastąp całą listę) | `add` | `remove`; `phrases`: niepusta lista napisów.
- Frazy są normalizowane (małe litery, bez interpunkcji), a porównywane dodatkowo bez polskich znaków:
  `remove` z `"dyktuje"` usunie „dyktuję”, a `add` duplikatu nic nie zmieni.
- Odrzucane z `{"ok": false, "error": "..."}` (komunikat po polsku, gotowy do pokazania): pusta fraza,
  usunięcie ostatniej frazy startu, fraza jednocześnie startu i stopu, `remove` frazy, której nie ma.
- Zmiana jest zapisywana na stałe (w `~/.config/ptt/config.toml`) i działa od razu, bez restartu.

### Odpowiedzi

Każda komenda (poza `subscribe`, która zwraca samo `{"ok": true}`) dostaje dokładnie jedną odpowiedź:
```json
{"ok": true, "server": "ready", "dictation": "listening", "pending": 0, "wake": false}
{"ok": false, "error": "nieznana komenda: foo"}
```
Wyjątek: `wake_config`, `wake_phrases` i `wake_autostart` zwracają ustawienia zamiast stanu:
```json
{"ok": true, "start_phrases": ["dyktuję"], "stop_phrases": ["full stop", "koniec dyktowania"], "wake_on_start": false}
```
**Odpowiedzi nie mają pola `event`, zdarzenia zawsze je mają**. Tak je odróżniać na wspólnym połączeniu.
Dane z odpowiedzi nie są potrzebne do UI, bo każda zmiana i tak przychodzi jako zdarzenie
(`state` albo `wake_config`); z odpowiedzi wystarczy `ok`/`error`, np. do pokazania błędu przy edycji fraz.

## Zdarzenia (demon → klient, po `subscribe`)

### `state`: pełny stan, wysyłany przy każdej zmianie
```json
{"event": "state", "server": "ready", "dictation": "speaking", "pending": 0, "wake": false}
```
- `server`:
  - `off`: serwer wyłączony (np. celowo, dla VRAM),
  - `loading`: startuje / ładuje model,
  - `ready`: gotowy,
  - `error`: usługa padła (systemd: failed).
- `dictation` (tylko aktywne dyktowanie, czyli wpisywanie tekstu):
  - `idle`: dyktowanie wyłączone (przy `wake: true` mikrofon i tak słucha, czekając na frazę startu),
  - `listening`: dyktowanie włączone, cisza,
  - `speaking`: dyktowanie włączone, wykryto mowę (zmienia się często, z każdą pauzą).
- `pending`: liczba fragmentów mowy czekających na przepisanie i wpisanie. `> 0` oznacza „przetwarzam”.
  Po wyłączeniu dyktowania może jeszcze przez chwilę być `> 0` (ostatnie słowa są dopisywane).
  Sprawdzanie frazy startu w trybie wake **nie** zwiększa `pending`.
- `wake` (bool): tryb słowa kluczowego włączony. Brak pola (stary demon) traktować jak `false`.

Zawsze nadpisywać cały stan wartościami z najnowszego zdarzenia.

### `wake_config`: ustawienia trybu wake
```json
{"event": "wake_config", "start_phrases": ["dyktuję"], "stop_phrases": ["full stop", "koniec dyktowania", "stop dyktowania", "zakończ dyktowanie", "wyłącz dyktowanie"], "wake_on_start": false}
```
Przychodzi zaraz po `subscribe` i przy każdej zmianie ustawień, niezależnie od tego, kto je zmienił
(ten klient, inny klient, CLI `ptt wake phrases …`). Panel ustawień powinien pokazywać zawsze
ostatnie `wake_config`, a nie lokalną kopię po własnej edycji.
- `start_phrases`: frazy włączające dyktowanie (wypowiedź musi się od nich **zaczynać**),
- `stop_phrases`: frazy wyłączające dyktowanie (cała wypowiedź); działają też bez trybu wake,
- `wake_on_start`: tryb wake włącza się sam przy starcie demona (czyli przy logowaniu).

### `partial`: podgląd na żywo (tymczasowy)
```json
{"event": "partial", "text": "no więc chciałem powiedzieć że"}
```
Tekst bieżącego, jeszcze niezakończonego fragmentu, ~2 razy na sekundę, gdy użytkownik mówi.
Obejmuje cały fragment, także słowa już wpisane w trakcie mówienia (`final` z `commit: true`).
Może się zmieniać między zdarzeniami (whisper poprawia się w miarę dopływu audio). Każdy kolejny
`partial` **zastępuje** poprzedni. `text: ""` oznacza „wyczyść podgląd” (fragment się skończył).
Ten tekst niczego nie wpisuje, jest tylko do wyświetlania. W trybie wake, przed frazą startu, `partial`
nie przychodzi (demon nie pokazuje, co słyszy, dopóki dyktowanie nie jest aktywne).

### `final`: coś zostało wpisane w aktywne okno
```json
{"event": "final", "commit": false, "text": " który jest czarny.", "actions": [
  {"type": "key", "key": "BackSpace", "count": 1},
  {"type": "text", "text": " który jest czarny."}
]}
```
- `text`: tekst wpisany tym razem (może zaczynać się spacją; może być pusty, gdy były tylko klawisze),
- `actions`: dokładnie to, co zostało wykonane na klawiaturze (`text` = wpisany tekst,
  `key` = naciśnięcia klawisza, nazwy keysym xkb: `BackSpace`, `Return`, ...; opcjonalne `mods`,
  np. `["ctrl"]` dla Ctrl+C),
- `commit`: `true`, gdy to słowa wpisane jeszcze w trakcie mówienia (zatwierdzone, bo kilka kolejnych
  podglądów się zgadzało); `false`, gdy to zamknięcie fragmentu po pauzie. Fragment może dać kilka
  `final` z `commit: true` i na końcu jeden z `commit: false`, który ewentualnie poprawia wcześniejsze
  słowa (stąd BackSpace w `actions`).

Do UI zwykle wystarczy `text`, np. żeby po zakończeniu fragmentu przez chwilę pokazać to, co wpisano.

### `command`: wykonano komendę głosową
```json
{"event": "command", "name": "delete_words"}
```
Nazwy:
- `wake`: fraza startu włączyła dyktowanie (tryb wake),
- `stop`: fraza stopu wyłączyła dyktowanie (w trybie wake: powrót do nasłuchu),
- `newline`, `paragraph`, `punctuation`, `symbol` („znak …”), `key` („klawisz …”), `number` („liczba …”),
- `delete_words`, `delete_sentence`, `delete_line`, `undo`,
- `noop`: komenda rozpoznana, ale nie było czego usunąć.

Nadaje się na krótki wskaźnik w pasku (np. „↵”, „⌫ słowo”, „↶ cofnij”, „▶ dyktuję”, „■ koniec”).
Zmiana stanu po `wake`/`stop` przychodzi też jako `state`.

### `error`
```json
{"event": "error", "message": "whisper-server niedostępny"}
```
Błąd, który użytkownik powinien zauważyć (np. fragment nie został wpisany, mikrofon przestał działać).
Nadaje się na krótkie powiadomienie. Gdy mikrofon przestanie działać, tryb wake wyłącza się sam (`wake: false`).

## Tryb słowa kluczowego (wake)

Dwa niezależne przełączniki, oba widoczne w `state`:

| `wake` | `dictation` | co się dzieje | jak użytkownik tu trafia |
|--------|-------------|---------------|--------------------------|
| `false` | `idle` | mikrofon wyłączony | `wake_off`, `stop` |
| `false` | `listening`/`speaking` | dyktowanie ręczne, wpisuje | `toggle`/`start` |
| `true` | `idle` | mikrofon włączony, **nic nie wpisuje**, czeka na frazę startu | `wake_on`; fraza stopu; `toggle`/`stop` przy aktywnym dyktowaniu |
| `true` | `listening`/`speaking` | dyktowanie aktywne, wpisuje | fraza startu (`command` `wake`) albo `toggle`/`start` |

Zasady:
- przy `wake: true` `toggle`/`stop`/`hold_stop` wyłączają tylko dyktowanie: demon wraca do nasłuchu frazy,
  mikrofon zostaje włączony,
- mikrofon całkiem wyłącza dopiero `wake_off` (albo `server_stop`); przy aktywnym dyktowaniu `wake_off`
  zostawia dyktowanie włączone, a kolejny `stop` zamyka mikrofon,
- fraza startu musi **zaczynać** wypowiedź; reszta tej samej wypowiedzi jest wpisywana
  („dyktuję, ala ma kota” → wpisze „Ala ma kota”),
- w nasłuchu demon sprawdza tylko krótkie wypowiedzi (do ~3 s mowy), dłuższa rozmowa jest ignorowana,
- przy włączeniu i wyłączeniu frazą demon sam odtwarza krótki dźwięk; Quickshell nie musi tego robić.

Ustawienia (frazy, autostart) zmienia się komendami `wake_phrases`/`wake_autostart` albo z CLI
(`ptt wake phrases …`, `ptt wake autostart on|off`); aktualny stan zawsze przychodzi w `wake_config`.

## Sugerowany UX

Ikona mikrofonu w pasku + jedna linia tekstu obok.

| stan | ikona | tekst |
|------|-------|-------|
| brak połączenia z demonem | przekreślona, wyszarzona | — |
| `server: off` | szara | — |
| `server: loading` | przygaszona, pulsuje | — |
| `server: error` | czerwona / ostrzeżenie | — |
| `server: ready`, `dictation: idle`, `wake: false` | normalna | — |
| `wake: true`, `dictation: idle` | inna ikona („ucho”) albo mała kropka/obwódka akcentu: mikrofon słucha, czeka na frazę | opcjonalnie podpowiedź `powiedz „dyktuję”` (pierwsza z `start_phrases`) |
| `dictation: listening` | aktywna (akcent) | ostatni `partial`/`final` albo nic |
| `dictation: speaking` | aktywna, pulsuje / czerwona | `partial` na żywo |
| `pending > 0` | dodatkowy wskaźnik „przetwarzam” | |

Stan `wake: true` + `dictation: idle` musi być wyraźnie inny niż zwykły `idle`, bo mikrofon jest wtedy
włączony. Przy aktywnym dyktowaniu `wake: true` może być pokazane dyskretnie (np. mała ikonka „ucha”),
żeby było wiadomo, że po frazie stopu demon wróci do nasłuchu, a nie wyłączy mikrofon.

- Linia podglądu: pokazuje ostatni niepusty `partial`. Po `partial` z `text: ""` można przez ~2–3 s
  pokazywać `text` z ostatniego `final`, a potem wygasić. Długi tekst przycinać **od lewej**
  (widać koniec, czyli najnowsze słowa), w jednej linii, z elizją na początku.
- Kliknięcia:
  - LPM: `toggle` (dyktowanie),
  - ŚPM (albo LPM z modyfikatorem): `wake_toggle`,
  - PPM: menu:
    - „Nasłuch słowa kluczowego” (checkbox wg `wake`, `wake_toggle`),
    - „Nasłuch od startu” (checkbox wg `wake_on_start` z `wake_config`, `wake_autostart`),
    - „Frazy…” (panel ustawień, niżej),
    - włącz/wyłącz serwer (`server_start`/`server_stop` zależnie od stanu), `server_restart`.
- `command` `wake`/`stop`: krótki wskaźnik („▶ dyktuję”, „■ koniec”) przez ~1–2 s.
- `error`: powiadomienie.

### Panel ustawień fraz (opcjonalny)

Dwie listy: „Start” (`start_phrases`) i „Stop” (`stop_phrases`) z ostatniego `wake_config`.
- przy każdej frazie przycisk usuń → `{"cmd":"wake_phrases","kind":"start","op":"remove","phrases":["…"]}`,
- pole tekstowe + dodaj → `op: "add"`,
- błąd z odpowiedzi (`ok: false`) pokazać przy polu (np. „potrzebna co najmniej jedna fraza startu”);
  przycisk usuwania ostatniej frazy startu można od razu wyszarzyć,
- listy odświeżać tylko ze zdarzenia `wake_config` (przyjdzie po każdej udanej zmianie).

Wskazówka do pokazania w panelu: fraza startu powinna być nietypowa (słowo, którym rzadko zaczyna się
zwykłe zdanie), bo każda wypowiedź od niej zaczynająca się włączy dyktowanie.

Skróty klawiszowe (Hyprland) działają niezależnie od Quickshella i wołają te same komendy przez CLI `ptt`
(`SUPER+D`: `toggle`, `SUPER+SHIFT+D`: `wake_toggle`, `SUPER+ALT+D`: serwer), więc widget zawsze ma
aktualny stan ze zdarzeń, niezależnie od tego, skąd przyszła zmiana.

## Testowanie bez Quickshella

```bash
~/push-to-talk/bin/ptt watch      # podgląd strumienia zdarzeń
~/push-to-talk/bin/ptt toggle     # włącz/wyłącz dyktowanie
~/push-to-talk/bin/ptt wake toggle            # włącz/wyłącz tryb wake
~/push-to-talk/bin/ptt wake status            # tryb, autostart, frazy
~/push-to-talk/bin/ptt wake phrases start add "zacznij pisać"   # przyjdzie zdarzenie wake_config
# surowo, jak zrobi to klient:
socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/ptt/ctl.sock   # potem wpisać: {"cmd":"subscribe"}
```

## Stabilność protokołu

- Nowe pola i nowe typy zdarzeń mogą dojść w przyszłości. Klient **ignoruje nieznane pola i nieznane
  wartości `event`**, a nieznaną nazwę w `command` traktuje jak zwykłą komendę bez specjalnego wskaźnika.
- Istniejące pola i znaczenia wartości nie będą zmieniane bez aktualizacji tego dokumentu.
