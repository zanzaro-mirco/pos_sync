/// Il poco che le due parti devono sapere l'una dell'altra.
///
/// Sta in un file suo perché è l'unica cosa che server e client condividono:
/// tenerlo in uno dei due farebbe dipendere quel lato dall'altro, e non è così
/// — dipendono entrambi dal protocollo.
library;

/// Porta su cui il dispositivo primario ascolta.
///
/// Fissa e non configurabile: sopra 49152 sta l'intervallo effimero, che il
/// sistema assegna a chi non chiede una porta precisa, quindi non c'è il
/// rischio di litigare con un servizio noto. Renderla configurabile
/// aggiungerebbe un campo alle impostazioni e una cosa in più da sbagliare in
/// sala, per risolvere un problema che in una rete di ristorante non si pone.
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
