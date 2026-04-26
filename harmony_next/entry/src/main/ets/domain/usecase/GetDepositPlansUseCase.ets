import { WardrobeItem } from '../model/WardrobeItem';
import { WardrobeRepository } from '../repository/WardrobeRepository';

export class GetDepositPlansUseCase {
  private readonly repository: WardrobeRepository;

  constructor(repository: WardrobeRepository) {
    this.repository = repository;
  }

  executeAll(): Promise<WardrobeItem[]> {
    return this.repository.getDepositPlans();
  }

  executeByYear(year: number): Promise<WardrobeItem[]> {
    return this.repository.getDepositPlansByYear(year);
  }
}
