import type { WardrobeItem } from '../model/WardrobeItem';
import type { WardrobeRepository } from '../repository/WardrobeRepository';
export class GetWardrobeItemsUseCase {
    private readonly repository: WardrobeRepository;
    constructor(repository: WardrobeRepository) {
        this.repository = repository;
    }
    execute(): Promise<WardrobeItem[]> {
        return this.repository.getActiveItems();
    }
}
