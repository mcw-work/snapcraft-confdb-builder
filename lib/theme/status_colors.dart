import 'package:flutter/material.dart';

import '../models/diagnostic.dart';

Color diagnosticColor(BuildContext context, DiagnosticSeverity severity) =>
    severity == DiagnosticSeverity.blocker
    ? Theme.of(context).colorScheme.error
    : Theme.of(context).colorScheme.tertiary;