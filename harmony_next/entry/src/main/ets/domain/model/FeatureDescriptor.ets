import { AppRoute } from '../../core/navigation/AppRoute';

export interface FeatureDescriptor {
  readonly route: AppRoute;
  readonly title: string;
  readonly description: string;
  readonly milestone: string;
  readonly status: 'planned' | 'scaffolded' | 'in_progress' | 'done';
}
