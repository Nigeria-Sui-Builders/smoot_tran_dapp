export const deactivateVerifierTransaction = async (
  verifierId: string
): Promise<SuiTransactionBlockResponse> => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${ENV.PACKAGE_ID}::trade_vault::deactivate_verifier`,
    arguments: [tx.object(verifierId)],
    typeArguments: [],
  });

  return suiClient.signAndExecuteTransaction({
    transaction: tx,
    signer: getSigner({ secretKey: ENV.USER_SECRET_KEY }),
    options: { showEffects: true, showObjectChanges: true },
  });
};
