import { WardrobeRepository } from '../repository/WardrobeRepository';

export class ReorderWardrobeItemsUseCase {
  private readonly repository: WardrobeRepository;

  constructor(repository: WardrobeRepository) {
    this.repository = repository;
  }

  execute(orderedIds: string[]): Promise<void> {
    return this.repository.reorderItems(orderedIds);
  }
}
