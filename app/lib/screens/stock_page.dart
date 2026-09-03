import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api.dart';
import '../api/financial_api.dart';
import '../models/stock.dart';
import '../models/financial.dart';
import '../page/financial/financial_tab.dart';
import '../page/technical/technical_tab.dart';
import '../page/institution/institution_tab.dart';
import '../page/news/news_tab.dart';
import '../page/investor_meeting/investor_meeting_tab.dart';
import '../page/major_event/major_event_tab.dart';
import '../page/ebook/ebook_tab.dart';
import '../page/main_tabs/pick_watchlist_dialog.dart';


class StockPage extends StatefulWidget {

  final String stockCode;
  final String stockName;


  const StockPage({
    super.key,
    required this.stockCode,
    required this.stockName,
  });


  @override
  State<StockPage> createState() => _StockPageState();

}



class _StockPageState extends State<StockPage> {

  Stock? stock;
  FinancialData? financial;

  bool loading = true;

  String? error;
  String formatPrice(double price) {
  if (price >= 1000) {
    return price.toStringAsFixed(0);
  } else if (price >= 100) {
    return price.toStringAsFixed(1);
  } else {
    return price.toStringAsFixed(2);
  }
  }



  @override
  void initState() {

    super.initState();

    loadStock();

  }





  Future<void> loadStock() async {


    setState(() {

      loading = true;

      error = null;

    });



    try {


      final data = await ApiService.getStock(
        widget.stockCode,
      );

      final financialData =
          await FinancialApi.getFinancial(widget.stockCode);

      print(financialData.quarter.length);

      if (financialData.quarter.isNotEmpty) {
        print(financialData.quarter.last.eps);
      }



      setState(() {

        stock = data;
        financial = financialData;

        loading = false;

      });



    } catch(e) {


      setState(() {

        error = e.toString();

        loading = false;

      });


    }


  }






  @override
  Widget build(BuildContext context) {


    return DefaultTabController(
      length: 8,
      child: Scaffold(


      appBar: AppBar(
        title: Text(
          '${widget.stockCode} ${widget.stockName}',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: "加入自選股",
            onPressed: () {
              showPickWatchlistDialog(
                context,
                code: widget.stockCode,
                name: widget.stockName,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadStock,
          ),
        ],
        bottom: const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: '首頁'),
            Tab(text: '技術'),
            Tab(text: '法人'),
            Tab(text: '財務'),
            Tab(text: '新聞'),
            Tab(text: '重大動態'),
            Tab(text: '法人/股東會'),
            Tab(text: '電子書'),
          ],
        ),
      ),

      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : error != null
              ? Center(
                  child: Text(error!),
                )
              : TabBarView(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [




                Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [

    Text(
      '${stock!.code} ${stock!.name}',
      style: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
    ),

    const SizedBox(height: 4),

    Text(
      stock!.industry,
      style: const TextStyle(
        fontSize: 16,
        color: Colors.grey,
      ),
    ),

    if (stock!.website != null) ...[
      const SizedBox(height: 6),
      InkWell(
        onTap: () async {
          final uri = Uri.tryParse(stock!.website!);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.language,
              size: 16,
              color: Colors.blue.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              "公司網址：",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            Expanded(
              child: Text(
                stock!.website!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.shade600,
                  decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ],

  ],
),




                const SizedBox(height:25),




                const SizedBox(height:20),





                const Text(

                  '📈 股價資訊',

                  style: TextStyle(

                    fontSize:22,

                    fontWeight:FontWeight.bold,

                  ),

                ),





                Card(
  elevation: 3,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  ),
  child: Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatPrice(stock!.price),
          style: const TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "今日股價",
          style: TextStyle(color: Colors.grey),
        ),
        const Divider(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _info("開盤", formatPrice(stock!.open)),
            _info("最高", formatPrice(stock!.high)),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _info("最低", formatPrice(stock!.low)),
            _info("收盤", formatPrice(stock!.close)),
          ],
        ),
        const Divider(height: 30),
        if (!stock!.financialSupported)

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              "此商品不適用財報分析（ETF／ETN／黃金等）",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          )

        else
          Column(
            children: [

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _info(
                    "近四季 EPS",
                    stock!.epsTtm?.toStringAsFixed(2) ?? "-",
                  ),
                  _info(
                    "本益比",
                    stock!.pe?.toStringAsFixed(2) ?? "-",
                  ),
                ],
              ),

              const SizedBox(height: 15),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _info(
                    "股價淨值比",
                    stock!.pb?.toStringAsFixed(2) ?? "-",
                  ),
                  _info(
                    "殖利率",
                    stock!.dividendYield == null
                        ? "-"
                        : "${stock!.dividendYield!.toStringAsFixed(2)}%",
                  ),
                ],
              ),
            ],
          ),
      ],
    ),
  ),
),





                const SizedBox(height:20),





                const Text(

                  '🤖 AI 分析',

                  style: TextStyle(

                    fontSize:22,

                    fontWeight:FontWeight.bold,

                  ),

                ),




                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Text(
                      stock!.financialSupported
                          ? '等待 AI 分析財報、新聞與法說會資料'
                          : '此商品不適用財報分析，可查看價格、技術分析及相關資訊。',
                    ),
                  ),
                ),





                const SizedBox(height:20),




                const Text(

                  '💬 討論區',

                  style: TextStyle(

                    fontSize:22,

                    fontWeight:FontWeight.bold,

                  ),

                ),




                const Card(

                  child: ListTile(

                    title: Text(
                      '目前尚無討論',
                    ),

                  ),

                ),



              
                        ],
                      ),
                    ),
                    TechnicalTab(
                      code: stock!.code,
                    ),
                    InstitutionTabPage(
                      code: stock!.code,
                    ),
                    FinancialTab(
                      financial: financial!,
                      stock: stock!,
                    ),
                    NewsTab(
                      code: stock!.code,
                    ),
                    MajorEventTab(
                      code: stock!.code,
                    ),
                    InvestorMeetingTab(
                      code: stock!.code,
                    ),
                    EbookTab(
                      code: stock!.code,
                    ),
                  ],
                ),
    ),
  );


  }




  Widget _info(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

}