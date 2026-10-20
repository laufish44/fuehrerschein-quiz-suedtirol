import 'package:shared_preferences/shared_preferences.dart';

Future<String?> readFile(String name) async => (await SharedPreferences.getInstance()).getString('file:$name');

Future<void> writeFile(String name, String data) async {
  await (await SharedPreferences.getInstance()).setString('file:$name', data);
}

Future<String> location() async => 'Browser-Speicher';
