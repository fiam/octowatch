const repoOwner = "fiam";
const repoName = "octowatch";
const releasesURL = `https://github.com/${repoOwner}/${repoName}/releases`;
const latestReleaseURL = `https://api.github.com/repos/${repoOwner}/${repoName}/releases/latest`;

const downloadButton = document.getElementById("download-button");
const downloadCardLink = document.getElementById("download-card-link");
const releaseStatus = document.getElementById("release-status");

function preferredAsset(assets, exactName, suffix) {
  return assets.find((asset) => asset.name === exactName) ??
    assets.find((asset) => asset.name.endsWith(suffix));
}

function useFallback(message) {
  downloadButton.href = releasesURL;
  downloadButton.textContent = "View Releases";
  downloadCardLink.href = releasesURL;
  releaseStatus.textContent = message;
}

async function loadLatestRelease() {
  try {
    const response = await fetch(latestReleaseURL, {
      headers: {
        Accept: "application/vnd.github+json"
      }
    });

    if (!response.ok) {
      throw new Error(`GitHub API returned ${response.status}`);
    }

    const release = await response.json();
    const assets = release.assets ?? [];
    const dmg = preferredAsset(assets, "Octowatch.dmg", ".dmg");
    const zip = preferredAsset(assets, "Octowatch.zip", ".zip");

    if (!dmg && !zip) {
      useFallback("No packaged release is published yet. Source builds are available today.");
      return;
    }

    const primaryAsset = dmg ?? zip;
    downloadButton.href = primaryAsset.browser_download_url;
    downloadButton.textContent = `Download ${release.tag_name}`;
    downloadCardLink.href = primaryAsset.browser_download_url;

    const parts = [`Latest published release: ${release.tag_name}`];
    if (dmg) {
      parts.push("DMG available");
    }
    if (zip) {
      parts.push("ZIP available");
    }

    releaseStatus.textContent = `${parts.join(" · ")}.`;
  } catch (error) {
    useFallback("Release lookup is unavailable right now. Use GitHub Releases directly.");
  }
}

loadLatestRelease();
