// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_util/cli_logging.dart';

import '../model.dart';
import '../utils.dart';

class PackagesGetCommand extends Command {
  @override
  String get name => 'packages-get';

  @override
  String get description => "Run 'flutter pub get' in all DevTools packages.";

  @override
  Future run() async {
    final sdk = FlutterSdk.getSdk();
    if (sdk == null) {
      print('Unable to locate a Flutter sdk.');
      return 1;
    }

    final log = Logger.standard();
    final repo = DevToolsRepo.getInstance();
    final packages = repo.getPackages();

    log.stdout('Running flutter pub get...');

    int failureCount = 0;

    for (Package p in packages) {
      final progress = log.progress('  ${p.relativePath}');

      final process = await Process.start(
        sdk.flutterToolPath,
        ['packages', 'get'],
        workingDirectory: p.packagePath,
      );
      final stderr = process.stderr;

      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        progress.finish(showTiming: true);
      } else {
        failureCount++;

        // Display stderr when pub get goes wrong.
        final List<List<int>> err = await stderr.toList();
        final errorOutput = convertProcessOutputToString(err, '    ');
        progress.finish(message: 'failed (exit code $exitCode)');

        log.stderr(log.ansi.error(errorOutput));
      }
    }

    return failureCount == 0 ? 0 : 1;
  }
}
