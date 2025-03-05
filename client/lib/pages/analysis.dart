import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../utils/analysis_helper.dart';
import '../utils/database_helper.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  String inputText = "";
  bool isLoading = false;
  String? errorMessage;

  List<List<String>> suggestions = [];

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> getSuggestions(String query) async {
    setState(() {
      suggestions = [];
    });
    if (query.isEmpty) {
      return;
    }
    isLoading = true;
    try {
      List<List<String>> result = await AnalysisHelper.instance.getSuggestions(
        query,
      );
      if (result.isNotEmpty) {
        setState(() {
          suggestions = result;
        });
      } else {
        setState(() {
          suggestions = [];
          errorMessage = "未找到相关股票";
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "请求异常: $e";
      });
    } finally {
      isLoading = false;
    }
  }

  Future<void> start(int id) async {
    try {
      await AnalysisHelper.instance.start(id);
    } catch (e) {
      await DatabaseHelper.instance.updateStock(id, {'status': 9});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tdTheme = TDTheme.of(context);

    return Scaffold(
      backgroundColor: tdTheme.grayColor1,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '分析',
          style: TextStyle(
            color: tdTheme.fontGyColor1,
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: tdTheme.fontGyColor1),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TDSearchBar(
              controller: _searchController,
              placeHolder: '输入名称或股票代码搜索',
              alignment: TDSearchAlignment.center,
              onTextChanged: (text) {
                setState(() {
                  inputText = text;
                });
              },
              action: '搜索',
              onActionClick: (_) {
                getSuggestions(_searchController.text);
              },
            ),

            // 显示搜索建议
            if (suggestions.isNotEmpty && !isLoading)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                margin: const EdgeInsets.only(top: 4),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: suggestions.length > 10 ? 10 : suggestions.length,
                  separatorBuilder:
                      (context, index) =>
                          Divider(height: 1, color: tdTheme.grayColor3),
                  itemBuilder: (context, index) {
                    final item = suggestions[index];
                    return ListTile(
                      dense: true,
                      title: Text('${item[4]} (${item[3]})'),
                      onTap: () {
                        showGeneralDialog(
                          context: context,
                          pageBuilder: (
                            BuildContext buildContext,
                            Animation<double> animation,
                            Animation<double> secondaryAnimation,
                          ) {
                            return TDAlertDialog(
                              content: '开始分析 ${item[4]}(${item[3]})?',
                              rightBtnAction: () async {
                                // 保存到数据库
                                int id = await DatabaseHelper.instance
                                    .insertStock(
                                      item[4], // 股票名称
                                      item[3], // 股票代码
                                    );
                                start(id);
                                if (context.mounted) {
                                  Navigator.pushNamedAndRemoveUntil(
                                    context,
                                    "/",
                                    (route) => false,
                                  );
                                }
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),

            const SizedBox(height: 24),

            // 显示加载状态
            if (isLoading) const Center(child: TDCircleIndicator()),

            // 显示错误信息
            if (errorMessage != null && !isLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TDText(
                    errorMessage!,
                    textColor: tdTheme.errorColor6,
                    font: tdTheme.fontBodyMedium,
                  ),
                ),
              ),

            // 未搜索时显示提示
            if (suggestions.isEmpty && !isLoading)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(TDIcons.search, size: 64, color: tdTheme.grayColor6),
                      const SizedBox(height: 16),
                      TDText(
                        "输入股票代码或名称开始分析",
                        font: tdTheme.fontBodyLarge,
                        textColor: tdTheme.fontGyColor3,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
