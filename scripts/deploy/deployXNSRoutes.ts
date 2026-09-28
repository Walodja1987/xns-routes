/**
 * Deploy XNSRoutes
 *
 * USAGE:
 * `npx hardhat run scripts/deploy/deployXNSRoutes.ts --network sepolia`
 * `XNS_ROUTES_INITIAL_OWNER=0xYourOwner npx hardhat run scripts/deploy/deployXNSRoutes.ts --network sepolia`
 *
 * REQUIRED SETUP (Hardhat vars — see docs/DEV_NOTES.md):
 * - MNEMONIC
 * - ETHERSCAN_API_KEY (for verification on public networks)
 * - Network RPC, e.g. ETH_SEPOLIA_TESTNET_URL
 *
 * XNS registry (constructor arg):
 * - Default for `ethMain` / `sepolia`: `constants/addresses.ts` (`XNS_ADDRESS`)
 * - Override: `npx hardhat vars set XNS_CONTRACT_ADDRESS` or `XNS_CONTRACT_ADDRESS=0x...`
 *
 * Initial owner (constructor arg):
 * - Defaults to the deployer
 * - Override: `npx hardhat vars set XNS_ROUTES_INITIAL_OWNER` or
 *   `XNS_ROUTES_INITIAL_OWNER=0x...`
 *
 * After deployment, record the address in constants/addresses.ts (XNS_ROUTES_ADDRESS).
 *
 * The constructor is payable: it forwards `msg.value` to XNS `registerName("routes","xns")` so `routes@xns`
 * resolves to the new registry. The script queries `getNamespacePrice("xns")` on the XNS contract and
 * uses that as the deployment transaction value. The value must equal the price exactly: XNS refunds any
 * excess to the caller, and XNSRoutes has no `receive()` function, so an overpayment reverts the deployment.
 */

import { vars } from "hardhat/config";
import hre from "hardhat";
import { getAddress, isAddress } from "ethers";
import { XNS_ADDRESS } from "../../constants/addresses";

const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";

/** Deployer signer index (0 = first account from mnemonic) */
const deployerIndex = 3;

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function resolveXnsContractAddress(): string {
  const fromEnv = process.env.XNS_CONTRACT_ADDRESS?.trim();
  const fromVar = vars.has("XNS_CONTRACT_ADDRESS") ? vars.get("XNS_CONTRACT_ADDRESS").trim() : "";
  const fromConstants = XNS_ADDRESS[hre.network.name]?.trim() ?? "";
  const raw =
    fromEnv && fromEnv.length > 0 ? fromEnv : fromVar.length > 0 ? fromVar : fromConstants;
  if (!isAddress(raw)) {
    throw new Error(
      "Set a valid XNS registry address via constants/addresses.ts (XNS_ADDRESS), hardhat var XNS_CONTRACT_ADDRESS, or env XNS_CONTRACT_ADDRESS.",
    );
  }
  return getAddress(raw);
}

function resolveInitialOwner(deployer: string): string {
  const fromEnv = process.env.XNS_ROUTES_INITIAL_OWNER?.trim();
  const fromVar = vars.has("XNS_ROUTES_INITIAL_OWNER")
    ? vars.get("XNS_ROUTES_INITIAL_OWNER").trim()
    : "";
  const raw = fromEnv && fromEnv.length > 0 ? fromEnv : fromVar.length > 0 ? fromVar : deployer;

  if (!isAddress(raw) || getAddress(raw) === hre.ethers.ZeroAddress) {
    throw new Error(
      "Set XNS_ROUTES_INITIAL_OWNER to a valid non-zero address, or leave it unset to use the deployer.",
    );
  }

  return getAddress(raw);
}

function shouldVerifyOnExplorer(): boolean {
  const n = hre.network.name;
  return n !== "hardhat" && n !== "localhost";
}

async function main() {
  console.log("Deploying XNSRoutes...\n");

  const xnsAddress = resolveXnsContractAddress();
  console.log("XNS registry (constructor):", xnsAddress, "\n");

  const deployer = (await hre.ethers.getSigners())[deployerIndex];
  const initialOwner = resolveInitialOwner(deployer.address);
  console.log("Deploying with account:", deployer.address);
  console.log("Initial owner:", initialOwner);
  console.log(
    "Account balance:",
    hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)),
    "ETH\n",
  );

  const xnsPriceAbi = [
    "function getNamespacePrice(string namespace) external view returns (uint256)",
  ] as const;
  const xnsForPrice = new hre.ethers.Contract(xnsAddress, xnsPriceAbi, deployer);
  let registrationValue: bigint;
  try {
    registrationValue = await xnsForPrice.getNamespacePrice("xns");
    console.log(
      'XNS getNamespacePrice("xns"):',
      hre.ethers.formatEther(registrationValue),
      "ETH (sent with deployment for registerName)\n",
    );
  } catch {
    throw new Error(
      'Could not read getNamespacePrice("xns") on the XNS contract. Check XNS_CONTRACT_ADDRESS and network.',
    );
  }

  const XNSRoutes = await hre.ethers.getContractFactory("XNSRoutes", deployer);
  const xnsRoutes = await XNSRoutes.deploy(initialOwner, xnsAddress, {
    value: registrationValue,
  });
  await xnsRoutes.waitForDeployment();

  const contractAddress = await xnsRoutes.getAddress();
  console.log("XNSRoutes deployed to:", `${GREEN}${contractAddress}${RESET}\n`);

  if (!shouldVerifyOnExplorer()) {
    console.log(
      `${YELLOW}Skipping block explorer verification (local network).${RESET}\n` +
        "Done. Update constants/addresses.ts with the address above if needed.",
    );
    return;
  }

  console.log("Waiting 30 seconds before verification so the explorer can index the contract...\n");
  await delay(30_000);

  try {
    await hre.run("verify:verify", {
      address: contractAddress,
      constructorArguments: [initialOwner, xnsAddress],
    });
    console.log("\nVerification succeeded.");
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes("Already Verified")) {
      console.log("\nContract already verified.");
    } else {
      throw err;
    }
  }

  console.log(
    "\nDeployment finished. Record the address in constants/addresses.ts (XNS_ROUTES_ADDRESS) if applicable.",
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
