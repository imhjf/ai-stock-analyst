import 'package:http/http.dart' as http;

import 'database_helper.dart';
import 'package:charset/charset.dart';
import '../config/api.dart';

class AnalysisHelper {
  static final AnalysisHelper instance = AnalysisHelper._init();

  AnalysisHelper._init();

  // 开始
  Future<void> start(int id) async {
    Map data = await DatabaseHelper.instance.getStock(id);

    try {
      // URL编码查询参数
      final name = Uri.encodeComponent(data['name']);
      final code = data['code'];
      // 发送GET请求
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/start?name=$name&code=$code'),
      );
      if (response.statusCode == 200) {
        String sd = response.body.replaceAll('"', '');
        await DatabaseHelper.instance.updateStock(id, {'sd': sd, 'status': 1});
      } else {
        await DatabaseHelper.instance.updateStock(id, {'status': 9});
      }
    } catch (e) {
      print('Error start analysis: $e');
    }
  }

  // process
  Future<void> process(List<int> ids) async {
    try {
      // 获取股票信息
      final stocks = await DatabaseHelper.instance.getStocksByIds(ids);
      if (stocks.isEmpty) return;

      // 提取股票代码
      List<String> sdList = stocks.map((stock) => stock['sd'] as String).toList();
      if (sdList.isEmpty) return;

      // URL编码查询参数
      final sd = sdList.join(',');
      // 发送GET请求
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/process?sd=$sd'));

      if (response.statusCode == 200) {
        List<String> statusList = response.body.replaceAll('"', '').split(',');
        for (int i = 0; i < statusList.length; i++) {
          final status = statusList[i].trim();
          if (status == '1') {
            await DatabaseHelper.instance.updateStock(stocks[i]['id'], {
              'status': 2,
            });
          } else if (status == '-1') {
            await DatabaseHelper.instance.updateStock(stocks[i]['id'], {
              'status': 9,
            });
          }
        }
      }
    } catch (e) {
      print('Error processing stocks: $e');
      rethrow;
    }
  }

  // process
  Future<void> delete(List<int> ids) async {
    try {
      // 获取股票信息
      final stocks = await DatabaseHelper.instance.getStocksByIds(ids);
      if (stocks.isEmpty) return;

      // 提取股票代码
      List<String> sdList = stocks.map((stock) => stock['sd'] as String).toList();
      if (sdList.isEmpty) return;

      // URL编码查询参数
      final sd = sdList.join(',');
      // 发送GET请求
      await http.delete(Uri.parse('${ApiConfig.baseUrl}/delete?sd=$sd'));
    } catch (e) {
      print('Error deleting stocks: $e');
      rethrow;
    }
  }

  // retry
  Future<void> retry(int id) async {
    await DatabaseHelper.instance.updateStock(id, {'analyst_at': DateTime.now().toIso8601String()});
    await start(id);
  }

  // 获取股票建议
  Future<List<List<String>>> getSuggestions(String query) async {
    final List<List<String>> result = [];
    // 生成13位时间戳
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // URL编码查询参数
    final encodedQuery = Uri.encodeComponent(query);

    // 构建URL
    final url =
        'https://suggest3.sinajs.cn/suggest/type=&key=$encodedQuery&name=suggestdata_$timestamp';

    // 发送GET请求
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Accept': '*/*',
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': 'https://finance.sina.com.cn',
      },
    );
    if (response.statusCode == 200) {
      // 使用 GB2312 解码
      final gbk = Charset.getByName('gb2312');
      if (gbk == null) {
        throw Exception('GB2312 charset not found');
      }
      final body = gbk.decode(response.bodyBytes);
      // 提取数组部分
      final startIndex = body.indexOf('"');
      final endIndex = body.lastIndexOf('"');
      if (startIndex != -1 && endIndex != -1 && startIndex < endIndex) {
        final ListStr = body.substring(startIndex + 1, endIndex);
        final data = ListStr.split(';');
        if (data.isNotEmpty) {
          for (int i = 0; i < data.length; i++) {
            final parts = data[i].split(',');
            result.add(parts);
          }
        }
      }
    } else {
      throw ('"网络请求失败: ${response.statusCode}"');
    }
    return result;
  }
}
