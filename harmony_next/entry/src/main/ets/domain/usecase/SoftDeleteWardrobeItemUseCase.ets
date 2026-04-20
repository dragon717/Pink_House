import { WardrobeRepository } from '../repository/WardrobeRepository';

export class SoftDeleteWardrobeItemUseCase {
  private readonly repository: WardrobeRepository;

  constructor(repository: WardrobeRepository) {
    this.repository = repository;
  }

  execute(id: string): Promise<void> {
    return this.repository.softDeleteItem(id);
  }
}
