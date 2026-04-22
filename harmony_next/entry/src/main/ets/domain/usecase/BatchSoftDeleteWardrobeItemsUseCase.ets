import { WardrobeRepository } from '../repository/WardrobeRepository';

export class BatchSoftDeleteWardrobeItemsUseCase {
  private readonly repository: WardrobeRepository;

  constructor(repository: WardrobeRepository) {
    this.repository = repository;
  }

  execute(ids: string[]): Promise<void> {
    return this.repository.softDeleteItems(ids);
  }
}
