import "dart:async";
import "package:flutter/material.dart";
void main() => runApp(const MaterialApp(home: Probe()));
class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _ProbeState();
}
class _ProbeState extends State<Probe> {
  int count = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    debugPrint("PROBE_INIT=0");
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => count++);
      debugPrint("PROBE_TICK=$count");
    });
  }
  @override
  void reassemble() {
    super.reassemble();
    debugPrint("PROBE_REASSEMBLE=$count");
  }
  @override
  void dispose() { timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Fluttios protocol probe")),
    body: Center(child: Text("State: $count", style: const TextStyle(fontSize: 32))),
  );
}
