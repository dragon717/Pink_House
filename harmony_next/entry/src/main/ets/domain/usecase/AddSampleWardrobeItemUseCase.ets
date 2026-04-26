import { WardrobeItem } from '../model/WardrobeItem';
import { WardrobeRepository } from '../repository/WardrobeRepository';

export class AddSampleWardrobeItemUseCase {
  private readonly repository: WardrobeRepository;

  constructor(repository: WardrobeRepository) {
    this.repository = repository;
  }

  execute(): Promise<WardrobeItem> {
    return this.repository.addSampleItem();
  }
}
