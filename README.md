# Bacheca · widget per la schermata di blocco del Mac

Bacheca mette widget personalizzabili (meteo, musica con testi sincronizzati, calendario, promemoria, foto, note e altro) sulla schermata di blocco del Mac. Si dispongono liberamente in uno studio a tutto schermo, come i widget dell'iPhone. Richiede macOS 15 o successivo.

La cartella `prototype/` contiene il primo prototipo web della schermata di blocco, da aprire nel browser.

## Compilare e avviare

```bash
./build.sh
open build/Bacheca.app
```

L'app vive nella barra dei menu (icona con il lucchetto). Da lì apri **Impostazioni…** o **Disponi i widget…**.

**Disponi i widget** apre uno studio a tutto schermo sopra il tuo sfondo, con orologio e login finti per orientarti:
- trascina i widget dove vuoi; al centro dello schermo si agganciano e compare una guida gialla;
- tira la maniglia nell'angolo in basso a destra di un widget per cambiarne la dimensione: scatta alla più vicina tra S, M, L e XL;
- fai clic su un widget per scegliere la dimensione (S · M · L · XL), togliergli il riquadro, scegliere il colore (nota) o eliminarlo;
- fai clic su un widget nella barra in basso: si apre la galleria con l'anteprima dal vivo in tutte e quattro le dimensioni; fai clic su quella che vuoi o trascinala sullo schermo;
- trascina un widget sul cestino per toglierlo;
- **In righe** rimette tutto in righe ordinate sotto l'orologio; Esc o Fine per chiudere.

Per provarla davvero, blocca il Mac con ⌃⌘Q: i widget compaiono sopra la schermata di blocco e spariscono quando accedi.

## Widget

Come i widget dell'iPhone, ogni widget ha quattro dimensioni, ognuna con il suo layout: **S** piccolo (quadrato), **M** medio (rettangolo), **L** grande (quadrato grande), **XL** extra grande.

| Widget | Cosa cambia con la dimensione | Dati |
| --- | --- | --- |
| Meteo | S temperatura · M + condizioni · L + dettagli (percepita, umidità, vento, UV, pioggia, alba/tramonto) · XL tutto su due colonne | Open-Meteo, città a scelta |
| In riproduzione | S copertina a tutto riquadro · M/XL copertina + brano + avanzamento · L copertina grande sopra | Musica e Spotify |
| Testo della canzone | S riga attuale · M + successiva · XL tre righe · L sei righe | [LRCLIB](https://lrclib.net), posizione da Musica o Spotify |
| Calendario | S giorno · M giorno + settimana · L mese · XL giorno, evento e mese | Calendario |
| Prossimi eventi | S il prossimo · M uno · L tre · XL tre su due colonne | Calendario (chiede il permesso) |
| Promemoria | S quanti ne restano · M due · L sei · XL otto su due colonne | Promemoria (chiede il permesso) |
| Foto | riempie il riquadro | cartella a scelta, cambia ogni 1–60 minuti |
| Nota adesiva | testo più grande nei formati grandi | testo e colore a scelta |
| Orologio, Fuso orario | S quadrante · M/XL quadrante + ora digitale · L quadrante grande | calcolati sul Mac |
| Batteria, Giornata | S anello · M anello + testo · L anello grande · XL + barra | calcolati sul Mac |
| Fase lunare | S luna · M/XL + nome, % e prossima luna piena · L luna grande | calcolata sul Mac |
| Conto alla rovescia | S giorni · M/XL nome, data e giorni · L numero grande | data a scelta |

Al massimo 16 widget. Ogni widget (tranne nota e foto) può stare senza riquadro, direttamente sullo sfondo.

Stili dei riquadri: Vetro, Vetro colorato, Scuro, Chiaro, Pieno, Contorno, Senza sfondo. Colore, dimensione generale e carattere (Standard, Arrotondato, Serif, Mono) si scelgono nelle impostazioni.

`open build/Bacheca.app --args --preview` apre subito lo studio, utile mentre si sviluppa.

## Come funziona

- La finestra dei widget viene spostata in uno "spazio" privato del WindowServer sopra la schermata di blocco, con le API non documentate di SkyLight (tecnica di [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow), licenza MIT). Possono smettere di funzionare con un aggiornamento di macOS: in quel caso le impostazioni lo segnalano e l'anteprima continua a funzionare.
- La finestra sulla schermata di blocco non riceve né clic né tastiera, quindi non interferisce con il campo della password.
- Un controllo ogni 2 secondi nasconde i widget se il Mac risulta sbloccato, anche se la notifica di sblocco si perde.
- La firma è ad-hoc: l'app funziona su questo Mac, non è pronta per essere distribuita.

## File

- `SkyLight.swift`: lo spazio sopra la schermata di blocco
- `AppDelegate.swift`: barra dei menu, eventi di blocco/sblocco, finestre
- `Widgets.swift`: layout e grafica dei widget
- `Studio.swift`: studio a posizione libera, barra dei widget, opzioni del widget selezionato, cestino
- `Services.swift`: meteo, musica, batteria, calendario
- `SettingsView.swift`: finestra delle impostazioni
- `Config.swift`: modello e salvataggio delle preferenze

## Licenza

Bacheca è distribuita con licenza [MIT](LICENSE). Il codice ripreso da SkyLightWindow e i servizi usati (Open-Meteo, LRCLIB) sono elencati in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
