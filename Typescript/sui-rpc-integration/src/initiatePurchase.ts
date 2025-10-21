export const initiatePurchaseTransaction = async (
  vaultId: string,
  paymentCoinId: string,
  requiredVerifications: number
): Promise<SuiTransactionBlockResponse> => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${ENV.PACKAGE_ID}::trade_vault::initiate_purchase`,
    arguments: [
      tx.object(vaultId),
      tx.object(paymentCoinId),
      tx.pure.u8(requiredVerifications),
      tx.object(ENV.CLOCK_ID),
    ],
    typeArguments: [],
  });

  return suiClient.signAndExecuteTransaction({
    transaction: tx,
    signer: getSigner({ secretKey: ENV.USER_SECRET_KEY }),
    options: { showEffects: true, showObjectChanges: true },
  });
};
