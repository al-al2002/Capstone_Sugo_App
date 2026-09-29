import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'core/constants/app_strings.dart';
import 'core/routing/app_router.dart';
import 'core/routing/app_routes.dart';
import 'core/services/supabase_service.dart';
import 'core/session/session_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/sugo_offline_banner.dart';
import 'features/auth/data/repositories/auth_repository.dart';
import 'features/auth/data/repositories/supabase_auth_repository.dart';
import 'features/auth/presentation/controllers/auth_controller.dart';

/// Root widget: wires up dependencies, then hands off to the router.
class SugoApp extends StatelessWidget {
  const SugoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        // One repository for the whole app; screens create their own
        // short-lived controllers on top of it.
        Provider<AuthRepository>(
          create: (_) => SupabaseAuthRepository(SupabaseService.client),
        ),
        ChangeNotifierProvider<AuthController>(
          create: (BuildContext context) =>
              AuthController(context.read<AuthRepository>()),
        ),
        // Loads profiles.role and the technician's verification state, and
        // exposes the single LandingDestination that AuthGate switches on.
        // App-wide because the technician dashboard also writes back to it
        // when the availability toggle changes.
        ChangeNotifierProvider<SessionController>(
          create: (_) => SessionController(),
        ),
      ],
      child: MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: AppRoutes.root,
        onGenerateRoute: AppRouter.onGenerateRoute,
        // Above the navigator, so the offline strip is present on every
        // screen - including dialogs and pushed routes - without any screen
        // having to know about it.
        builder: (BuildContext context, Widget? child) =>
            SugoOfflineBanner(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
