import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'models/analytics.dart';
import 'repositories/company_repository.dart';
import 'repositories/delivery_repository.dart';
import 'repositories/metrics_repository.dart';
import 'repositories/pipeline_repository.dart';

/// The one HTTP client, shared by every repository so they share a token pair.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>(
  (Ref ref) => ApiClient.instance,
);

final Provider<CompanyRepository> companyRepositoryProvider =
    Provider<CompanyRepository>(
      (Ref ref) => CompanyRepository(ref.watch(apiClientProvider)),
    );

final Provider<MetricsRepository> metricsRepositoryProvider =
    Provider<MetricsRepository>(
      (Ref ref) => MetricsRepository(ref.watch(apiClientProvider)),
    );

final Provider<PipelineRepository> pipelineRepositoryProvider =
    Provider<PipelineRepository>(
      (Ref ref) => PipelineRepository(ref.watch(apiClientProvider)),
    );

final Provider<DeliveryRepository> deliveryRepositoryProvider =
    Provider<DeliveryRepository>(
      (Ref ref) => DeliveryRepository(ref.watch(apiClientProvider)),
    );

/// The roster and its roll-ups - what `MockCompany.instance` used to be, minus
/// the assumption that it is already in memory.
///
/// Everything else derives from this, so a screen that edits a person calls
/// [refreshCompany] and every dependent view reloads with it.
final FutureProvider<CompanySnapshot> companyProvider =
    FutureProvider<CompanySnapshot>(
      (Ref ref) => ref.watch(companyRepositoryProvider).load(),
    );

/// Invalidates the roster after a write, so the tables show the new state.
/// Dependent providers rebuild on their own.
void refreshCompany(Ref ref) => ref.invalidate(companyProvider);

/// Whoever is signed in. The top bar used to show a hardcoded name, which was
/// wrong for every account but one.
final FutureProvider<SignedInUser> currentUserProvider =
    FutureProvider<SignedInUser>(
      (Ref ref) => ref.watch(companyRepositoryProvider).me(),
    );

/// Leads plus their activity timelines.
final FutureProvider<PipelineSnapshot> pipelineProvider =
    FutureProvider<PipelineSnapshot>((Ref ref) async {
      final CompanySnapshot company = await ref.watch(companyProvider.future);
      return ref
          .watch(pipelineRepositoryProvider)
          .load(company.leads, company.visitRows);
    });

/// How many days the dashboard looks back. The 7d / 14d / 30d control
/// writes it; the KPI load re-runs with it.
final StateProvider<int> dashboardDaysProvider = StateProvider<int>(
  (Ref ref) => 14,
);

/// Dashboard KPI tiles.
final FutureProvider<KpiSnapshot> kpiProvider = FutureProvider<KpiSnapshot>((
  Ref ref,
) async {
  final CompanySnapshot company = await ref.watch(companyProvider.future);
  final int days = ref.watch(dashboardDaysProvider);
  return ref.watch(metricsRepositoryProvider).kpis(company, days: days);
});

/// Text typed into the top-bar search. The Leads screen applies it and
/// clears it once consumed, so the box behaves like "jump to".
final StateProvider<String> globalSearchProvider = StateProvider<String>(
  (Ref ref) => '',
);

/// Ranked reps for the leaderboard, by metric.
final ProviderFamily<AsyncValue<List<LeaderboardEntry>>, LeaderboardMetric>
leaderboardProvider =
    Provider.family<AsyncValue<List<LeaderboardEntry>>, LeaderboardMetric>((
      Ref ref,
      LeaderboardMetric metric,
    ) {
      return ref
          .watch(companyProvider)
          .whenData(
            (CompanySnapshot company) => ref
                .watch(metricsRepositoryProvider)
                .repLeaderboard(company, metric),
          );
    });

/// Recent CRM movement, standing in for the audit feed the backend lacks.
final Provider<AsyncValue<List<ActivityItem>>> recentActivityProvider =
    Provider<AsyncValue<List<ActivityItem>>>((Ref ref) {
      return ref
          .watch(companyProvider)
          .whenData(
            (CompanySnapshot company) =>
                ref.watch(metricsRepositoryProvider).recentActivity(company),
          );
    });
