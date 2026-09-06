/// Il poco che le due parti devono sapere l'una dell'altra.
///
/// Sta in un file suo perché è l'unica cosa che server e client condividono:
/// tenerlo in uno dei due farebbe dipendere quel lato dall'altro, e non è così
/// — dipendono entrambi dal protocollo.
library;

/// Porta su cui il dispositivo primario ascolta.
///
/// Sopra 49152 sta l'intervallo effimero, quello che il sistema assegna a chi
/// non chiede una porta precisa: non c'è il rischio di litigare con un
/// servizio noto.
///
/// **Non si chiede a chi installa l'app.** Vale questo numero su entrambi i
/// lati, quindi nessuno deve impararlo dall'altro — come la 80 di HTTP, che si
/// scrive solo quando è diversa. Un campo nelle impostazioni non risolverebbe
/// nessun problema che in una rete di ristorante si ponga, e ne creerebbe uno
/// nuovo: basta sbagliarla su un tablet solo perché quel tablet non trovi più
/// la cassa, senza nessun errore da mostrare.
///
/// Resta un parametro nel codice per una ragione sola: i test chiedono la
/// porta `0`, cioè «una libera qualsiasi», e senza di essa due casi in
/// sequenza si contenderebbero la stessa.
const int lanPort = 53170;

/// Percorso delle versioni: `GET` per leggere quelle altrui, `POST` per
/// depositare la propria.
const String ordersPath = '/orders';

/// Percorso di riconoscimento: dice **chi** risponde, non solo che qualcuno
/// risponde.
///
/// È la differenza che conta per l'elezione: una connessione riuscita dice che
/// c'è un servizio sulla porta, non che sia il primario che ci si aspettava.
const String healthPath = '/health';

/// Nome del parametro con cui un dispositivo si presenta.
///
/// Il registro deve poter escludere le versioni di chi sta chiedendo, e per
/// farlo deve sapere chi è: senza questo, `fetchOrders` restituirebbe a ciascuno
/// anche la propria versione, che è un lavoro inutile nel migliore dei casi.
const String deviceParam = 'device';

/// Tipo di servizio annunciato via mDNS.
const String lanServiceType = '_possync._tcp';
