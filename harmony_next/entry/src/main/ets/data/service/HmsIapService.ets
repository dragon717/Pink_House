export interface PurchaseRequest {
  readonly productId: string;
  readonly payload?: string;
}

export interface PurchaseResult {
  readonly orderId: string;
  readonly productId: string;
  readonly purchaseData: string;
  readonly signature: string;
}

export class HmsIapService {
  async purchase(request: PurchaseRequest): Promise<PurchaseResult> {
    // TODO(M6): Replace this placeholder with @hms.core.iap.pay integration.
    throw new Error(`HMS IAP is not implemented yet: ${request.productId}`);
  }

  async restorePurchases(): Promise<PurchaseResult[]> {
    // TODO(M6): Query HMS owned purchases and reconcile local entitlement state.
    return [];
  }
}
