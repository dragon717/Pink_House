import type { WardrobeItem } from '../model/WardrobeItem';
import type { WardrobeRepository } from '../repository/WardrobeRepository';
export class SearchWardrobeItemsUseCase {
    private readonly repository: WardrobeRepository;
    constructor(repository: WardrobeRepository) {
        this.repository = repository;
    }
    execute(keyword: string): Promise<WardrobeItem[]> {
        return this.repository.searchActiveItems(keyword);
    }
}
