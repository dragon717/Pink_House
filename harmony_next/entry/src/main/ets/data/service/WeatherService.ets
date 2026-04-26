export interface WeatherSnapshot {
  readonly temperatureText: string;
  readonly conditionText: string;
  readonly refreshedAt: number;
}

export class WeatherService {
  async getTodayWeather(): Promise<WeatherSnapshot | undefined> {
    // TODO(F-55): Use @ohos.net.http and QWeather JWT. Cache successful results for 6h.
    return undefined;
  }
}
