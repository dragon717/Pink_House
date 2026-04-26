import { WardrobeItem } from '../model/WardrobeItem';
import {
  WardrobeFilterState,
  WardrobeSortOption
} from '../model/WardrobeListOptions';
import { WardrobeRepository } from '../repository/WardrobeRepository';

export class QueryWardrobeItemsUseCase {
  private readonly repository: WardrobeRepository;

  constructor(repository: WardrobeRepository) {
    this.repository = repository;
  }

  async execute(
    filter: WardrobeFilterState,
    sort: WardrobeSortOption,
    keyword: string
  ): Promise<WardrobeItem[]> {
    return this.repository.queryItems(filter, sort, keyword);
  }
}
