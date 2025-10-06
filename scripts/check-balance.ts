import "dotenv/config";
import { createPublicClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { bscTestnet } from "viem/chains";

const PRIVATE_KEY = process.env.PRIVATE_KEY as `0x${string}`;
const account = privateKeyToAccount(PRIVATE_KEY);

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http("https://bsc-testnet-rpc.publicnode.com"),
});

async function checkBalance() {
  const balance = await publicClient.getBalance({ address: account.address });
  console.log("Account:", account.address);
  console.log("tBNB Balance:", balance / BigInt(1e18));  // In tBNB
}

checkBalance();