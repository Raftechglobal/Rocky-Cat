import fs from "fs";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

const NUM_ENTRIES = 2500;
const TOKEN_AMOUNT = 1000n * 10n ** 18n; // 1000 tokens, 18 decimals

const recipients: string[] = [];
const amounts: string[] = []; // store as string for JSON

for (let i = 0; i < NUM_ENTRIES; i++) {
  const privateKey = generatePrivateKey();
  const account = privateKeyToAccount(privateKey);
  recipients.push(account.address);
  amounts.push(TOKEN_AMOUNT.toString()); // convert BigInt to string
}

// Save JSON
fs.writeFileSync(
  "airdrop.json",
  JSON.stringify({ recipients, amounts }, null, 2)
);

console.log(`✅ Generated airdrop.json with ${NUM_ENTRIES} entries`);
