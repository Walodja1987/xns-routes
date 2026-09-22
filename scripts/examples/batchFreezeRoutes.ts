/**
 * Permanently freeze multiple routes atomically.
 * Caller must be the current XNS owner of `label@namespace`.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/batchFreezeRoutes.ts --network <network_name>`
 */

import hre from "hardhat";
import { formatEther } from "ethers";
import { XNS_ROUTES_ADDRESS } from "../../constants/addresses";

const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const RED = "\x1b[31m";

/*//////////////////////////////////////////////////////////////
                            USER INPUTS
//////////////////////////////////////////////////////////////*/

const label = "xns";
const namespace = "action";
const routeLabels = ["register-name", "transfer-usdt"];
const signerIndex = 0;

async function main() {
  const networkName = hre.network.name;
  const { ethers } = hre;
  const contractAddress = XNS_ROUTES_ADDRESS[networkName];
  if (!contractAddress) {
    throw new Error(
      `XNSRoutes address not set for network: ${networkName}. Set XNS_ROUTES_ADDRESS in constants/addresses.ts`,
    );
  }
  if (routeLabels.length === 0) {
    throw new Error("Set at least one route label");
  }

  const routes = await ethers.getContractAt("XNSRoutes", contractAddress);
  const signer = (await ethers.getSigners())[signerIndex];

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`Signer: ${GREEN}${signer.address}${RESET}`);
  console.log(
    `Balance: ${GREEN}${formatEther(await ethers.provider.getBalance(signer.address))} ETH${RESET}`,
  );
  console.log(`XNS name: ${GREEN}${label}@${namespace}${RESET}`);
  console.log(`Route labels: ${GREEN}${routeLabels.join(", ")}${RESET}\n`);

  const tx = await routes.connect(signer).batchFreezeRoutes(label, namespace, routeLabels);
  console.log(`Transaction hash: ${GREEN}${tx.hash}${RESET}`);
  await tx.wait();

  for (const routeLabel of routeLabels) {
    const record = await routes["getRouteRecord(string,string,string)"](
      label,
      namespace,
      routeLabel,
    );
    console.log(`${label}@${namespace}/${routeLabel}: isFrozen=${record.isFrozen}`);
  }
  console.log(`${GREEN}✓ Confirmed.${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});
