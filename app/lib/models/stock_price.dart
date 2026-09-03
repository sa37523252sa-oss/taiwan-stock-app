class StockPrice {

  final double price;        // 最新價格
  final double change;       // 漲跌
  final double changePercent; // 漲跌幅
  final int volume;           // 成交量


  StockPrice({

    required this.price,

    required this.change,

    required this.changePercent,

    required this.volume,

  });

}