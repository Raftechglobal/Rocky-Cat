import fs from "fs";
import { parse } from "csv-parse/sync";

const csvData = fs.readFileSync("accounts.csv", "utf-8");
const records = parse(csvData, { columns: true, skip_empty_lines: true });

const recipients: string[] = [];
const amounts: string[] = [];

records.forEach((row: any, index: number) => {
  const holderAddress = row.HolderAddress?.trim();
  let balance = row.Balance?.replace(/,/g, ""); // Remove commas from balance

  // Skip if address or balance is missing or empty
  if (!holderAddress || !balance) {
    console.warn(`Skipping row ${index + 1}: Missing address or balance (Address: ${holderAddress}, Balance: ${balance})`);
    return;
  }

  // Validate Ethereum address (0x-prefixed, 40-character hex)
  if (!/^0x[a-fA-F0-9]{40}$/.test(holderAddress)) {
    console.warn(`Skipping row ${index + 1}: Invalid address format: ${holderAddress}`);
    return;
  }

  // Ensure balance is a valid number
  if (!/^\d*\.?\d*$/.test(balance) || isNaN(parseFloat(balance))) {
    console.warn(`Skipping row ${index + 1}: Invalid balance format: ${balance}`);
    return;
  }

  // Split balance into integer and decimal parts
  const [integerPart = "0", decimalPart = "0"] = balance.split(".");
  
  // Pad decimal part to 18 digits (standard for ERC20 tokens in wei)
  const paddedDecimal = decimalPart.padEnd(18, "0").slice(0, 18);

  try {
    // Convert to BigInt and compute wei
    const amountBigInt = BigInt(integerPart) * (10n ** 18n) + BigInt(paddedDecimal);

    // Skip if amount is zero
    if (amountBigInt === 0n) {
      console.warn(`Skipping row ${index + 1}: Zero balance for address ${holderAddress}`);
      return;
    }

    recipients.push(holderAddress);
    amounts.push(amountBigInt.toString());
  } catch (error) {
    console.warn(`Skipping row ${index + 1}: Error converting balance for address ${holderAddress}: ${balance} - ${error.message}`);
  }
});

if (recipients.length !== amounts.length) {
  throw new Error(`Array length mismatch: recipients (${recipients.length}) and amounts (${amounts.length}) must be equal`);
}

const airdropData = {
  recipients,
  amounts,
};

fs.writeFileSync("airdrop.json", JSON.stringify(airdropData, null, 2));
console.log(`✅ Generated airdrop.json with ${recipients.length} entries`);
