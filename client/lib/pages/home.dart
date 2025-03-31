import 'package:ai_stock_analysis/utils/analysis_helper.dart';
import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import '../utils/database_helper.dart';
import 'dart:async'; // Add Timer import
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import './report.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/api.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> stocks = [];
  bool isLoading = true;
  Timer? _timer;
  Set<int> _retryingIds = {}; // Add set to track retrying stocks
  bool _isLoadingStocks = false; // 添加锁变量
  bool _isSelectMode = false; // 添加选择模式状态
  Set<int> _selectedIds = {}; // 添加选中项集合
  Set<int> _downloadingIds = {}; // 添加下载状态集合
  bool _hasNewVersion = false; // 添加新版本检查状态
  String _currentVersion = ''; // 存储当前版本号

  @override
  void initState() {
    super.initState();
    loadStocks();
    _initPackageInfo();
    // Set up periodic timer to refresh stocks every 3 seconds
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_isLoadingStocks) {
        // 只有在没有正在加载的任务时才执行
        loadStocks();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel timer when widget is disposed
    super.dispose();
  }

  Future<void> _initPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _currentVersion = packageInfo.version;
    });
    checkVersion();
  }

  Future<void> loadStocks() async {
    if (_isLoadingStocks) return; // 如果正在加载，直接返回

    try {
      _isLoadingStocks = true; // 加锁
      setState(() {
        isLoading = true;
      });

      final stocksList = await DatabaseHelper.instance.getStocks();

      List<int> ids = [];
      for (int i = 0; i < stocksList.length; i++) {
        if (stocksList[i]['status'] == 1) {
          ids.add(stocksList[i]['id']);
        }
      }
      if (ids.isNotEmpty) {
        AnalysisHelper.instance.process(ids);
      }

      setState(() {
        stocks = stocksList;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading stocks: $e');
      setState(() {
        isLoading = false;
      });
    } finally {
      _isLoadingStocks = false; // 解锁
    }
  }

  Future<void> deleteSelectedStocks() async {
    final ids = _selectedIds.toList();
    try {
      await AnalysisHelper.instance.delete(ids);
    } catch (e) {}
    try {
      await DatabaseHelper.instance.deleteStockByIds(ids);
      setState(() {
        _selectedIds.clear();
        _isSelectMode = false;
      });
    } finally {
      await loadStocks();
    }
  }

  Future<void> retryAnalysis(int id) async {
    if (_retryingIds.contains(id)) return; // Prevent duplicate retry

    setState(() {
      _retryingIds.add(id);
    });

    try {
      await AnalysisHelper.instance.retry(id);
    } finally {
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _retryingIds.remove(id);
      });
    }
  }

  Future<void> previewReport(int id) async {
    if (_downloadingIds.contains(id)) return; // 防止重复点击

    final stock = stocks.firstWhere((s) => s['id'] == id);
    final url = Uri.parse(ApiConfig.getReportUrl(stock['sd']));

    try {
      setState(() {
        _downloadingIds.add(id);
      });

      // Get external storage directory (this is app-specific and doesn't require permissions)
      final appDir = await getExternalStorageDirectory();
      if (appDir == null) {
        throw Exception('无法访问存储目录');
      }

      // Create a reports directory inside app's external storage
      final reportsDir = Directory(path.join(appDir.path, 'reports'));
      if (!await reportsDir.exists()) {
        await reportsDir.create(recursive: true);
      }

      // Construct file path using sd
      final fileName = '${stock['sd']}.html';
      final file = File(path.join(reportsDir.path, fileName));

      if (await file.exists()) {
        // Open local file in WebView
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => ReportPage(
                    filePath: file.path,
                    title: '${stock['name']} 分析报告',
                  ),
            ),
          );
        }
        return;
      }

      // If file doesn't exist, download it
      final response = await http.get(url);
      if (response.statusCode == 200) {
        // Write file
        await file.writeAsBytes(response.bodyBytes);
        // Open the downloaded file in WebView
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => ReportPage(
                    filePath: file.path,
                    title: '${stock['name']} 分析报告',
                  ),
            ),
          );
        }
      } else {
        if (mounted) {
          TDToast.showText('无法下载报告', context: context);
        }
      }
    } catch (e) {
      print('Error previewing report: $e');
      if (mounted) {
        TDToast.showText('无法打开报告预览', context: context);
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingIds.remove(id);
        });
      }
    }
  }

  Future<void> checkVersion() async {
    if (_currentVersion.isEmpty) return;
    try {
      final response = await http.get(Uri.parse(ApiConfig.versionUrl));
      if (response.statusCode == 200) {
        final serverVersion = response.body.trim().replaceAll('"', '');
        // 简单的版本号比较，假设版本号格式为 x.y.z
        final serverParts = serverVersion.split('.');
        final currentParts = _currentVersion.split('.');
        bool isNewer = false;
        for (int i = 0; i < 3; i++) {
          final server = int.parse(serverParts[i]);
          final current = int.parse(currentParts[i]);
          if (server > current) {
            isNewer = true;
            break;
          } else if (server < current) {
            break;
          }
        }

        if (mounted) {
          setState(() {
            _hasNewVersion = isNewer;
          });
        }
      }
    } catch (e) {
      print('Error checking version: $e');
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
          'AI股票分析',
          style: TextStyle(
            color: tdTheme.fontGyColor1,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions:
            stocks.isEmpty
                ? null
                : [
                  if (_isSelectMode)
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: tdTheme.errorColor6,
                      ),
                      onPressed:
                          _selectedIds.isEmpty ? null : deleteSelectedStocks,
                    ),
                  IconButton(
                    icon: Icon(
                      _isSelectMode ? Icons.close : Icons.checklist,
                      color: tdTheme.fontGyColor1,
                    ),
                    onPressed: () {
                      setState(() {
                        _isSelectMode = !_isSelectMode;
                        if (!_isSelectMode) {
                          _selectedIds.clear();
                        }
                      });
                    },
                  ),
                ],
      ),
      body: Column(
        children: [
          if (_hasNewVersion)
            InkWell(
              onTap: () async {
                final url = Uri.parse(ApiConfig.downloadUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                color: tdTheme.brandColor1,
                child: Row(
                  children: [
                    Icon(
                      TDIcons.info_circle_filled,
                      color: tdTheme.brandColor7,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '新版本可用，点击下载',
                      style: TextStyle(
                        color: tdTheme.brandColor7,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      TDIcons.chevron_right,
                      color: tdTheme.brandColor7,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          isLoading
              ? const Expanded(child: Center(child: TDCircleIndicator()))
              : stocks.isEmpty
              ? Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        TDIcons.info_circle,
                        size: 64,
                        color: tdTheme.grayColor6,
                      ),
                      const SizedBox(height: 16),
                      TDText(
                        "暂无分析记录",
                        font: tdTheme.fontBodyLarge,
                        textColor: tdTheme.fontGyColor3,
                      ),
                    ],
                  ),
                ),
              )
              : Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: stocks.length,
                      separatorBuilder:
                          (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final stock = stocks[index];
                        final isSelected = _selectedIds.contains(stock['id']);
                        return GestureDetector(
                          onTap:
                              _isSelectMode
                                  ? () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedIds.remove(stock['id']);
                                      } else {
                                        _selectedIds.add(stock['id']);
                                      }
                                    });
                                  }
                                  : null,
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  isSelected
                                      ? tdTheme.brandColor1.withOpacity(0.1)
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              title: Text(stock['name']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(stock['code']),
                                      const SizedBox(width: 8),
                                      Text(
                                        DateTime.parse(
                                          stock['analyst_at'],
                                        ).toString().substring(0, 16),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: tdTheme.fontGyColor3,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              stock['status'] == 9
                                                  ? tdTheme.errorColor1
                                                  : stock['status'] == 3
                                                  ? tdTheme.successColor1
                                                  : stock['status'] == 2
                                                  ? tdTheme.successColor1
                                                  : stock['status'] == 1
                                                  ? tdTheme.warningColor1
                                                  : tdTheme.brandColor1,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          stock['status'] == 9
                                              ? '分析失败'
                                              : stock['status'] == 3
                                              ? '结束'
                                              : stock['status'] == 2
                                              ? '分析完成'
                                              : stock['status'] == 1
                                              ? '分析中'
                                              : '就绪',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                stock['status'] == 9
                                                    ? tdTheme.errorColor7
                                                    : stock['status'] == 3
                                                    ? tdTheme.successColor7
                                                    : stock['status'] == 9
                                                    ? tdTheme.successColor7
                                                    : stock['status'] == 2
                                                    ? tdTheme.warningColor7
                                                    : tdTheme.brandColor7,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (stock['status'] == 3 ||
                                      stock['status'] == 2)
                                    IconButton(
                                      icon:
                                          _downloadingIds.contains(stock['id'])
                                              ? SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(tdTheme.brandColor7),
                                                ),
                                              )
                                              : Icon(
                                                TDIcons.browse,
                                                color: tdTheme.brandColor7,
                                                size: 20,
                                              ),
                                      onPressed:
                                          _downloadingIds.contains(stock['id'])
                                              ? null
                                              : () async {
                                                await previewReport(
                                                  stock['id'],
                                                );
                                              },
                                    ),
                                  if (!_isSelectMode &&
                                      (stock['status'] == 9 ||
                                          (stock['status'] == 0 &&
                                              DateTime.now()
                                                      .difference(
                                                        DateTime.parse(
                                                          stock['analyst_at'],
                                                        ),
                                                      )
                                                      .inMinutes >=
                                                  1)))
                                    IconButton(
                                      icon:
                                          _retryingIds.contains(stock['id'])
                                              ? SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(tdTheme.brandColor7),
                                                ),
                                              )
                                              : Icon(
                                                TDIcons.refresh,
                                                color: tdTheme.brandColor7,
                                                size: 20,
                                              ),
                                      onPressed:
                                          _retryingIds.contains(stock['id'])
                                              ? null
                                              : () =>
                                                  retryAnalysis(stock['id']),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 62.0, right: 62.0),
        child: TDButton(
          icon: TDIcons.chart,
          theme: TDButtonTheme.primary,
          type: TDButtonType.fill,
          shape: TDButtonShape.circle,
          size: TDButtonSize.large,
          onTap: () async {
            await Navigator.pushNamed(context, '/analysis');
            loadStocks(); // 返回时重新加载列表
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
