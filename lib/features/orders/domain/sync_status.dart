/// Stato di sincronizzazione di un ordine, dal punto di vista del dispositivo.
enum SyncStatus {
  /// Salvato in locale, non ancora inviato.
  pending,

  /// Invio in corso.
  sending,

  /// Confermato dal server.
  synced,

  /// Rifiutato in modo definitivo: richiede intervento.
  failed,
}
