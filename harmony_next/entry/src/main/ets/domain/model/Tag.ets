export interface Tag {
  id: string;
  name: string;
  sortIndex: number;
  createdAt: number;
}

export interface NewTag {
  name: string;
  sortIndex?: number;
}
