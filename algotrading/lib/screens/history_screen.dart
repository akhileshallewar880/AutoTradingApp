import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/analysis_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final authProvider = context.read<AuthProvider>();
      final analysisProvider = context.read<AnalysisProvider>();
      await analysisProvider.loadHistory(authProvider.user!.accessToken);
    });
  }

  @override
  Widget build(BuildContext context) {
    final analysisProvider = context.watch<AnalysisProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: analysisProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : analysisProvider.history.isEmpty
              ? const Center(child: Text('No history'))
              : ListView.builder(
                  itemCount: analysisProvider.history.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text('Analysis ${index + 1}'),
                  ),
                ),
    );
  }
}
