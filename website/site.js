const repoOwner = "fiam";
const repoName = "octowatch";
const releasesURL = `https://github.com/${repoOwner}/${repoName}/releases`;
const repoURL = `https://github.com/${repoOwner}/${repoName}`;
const latestReleaseURL = `https://api.github.com/repos/${repoOwner}/${repoName}/releases/latest`;
const repoInfoURL = `https://api.github.com/repos/${repoOwner}/${repoName}`;

const downloadButton = document.getElementById("download-button");
const downloadCardLink = document.getElementById("download-card-link");
const releaseStatus = document.getElementById("release-status");
const latestTag = document.getElementById("latest-tag");
const repoStars = document.getElementById("repo-stars");
const starsLink = document.getElementById("stars-link");

function preferredAsset(assets, exactName, suffix) {
  return assets.find((asset) => asset.name === exactName) ??
    assets.find((asset) => asset.name.endsWith(suffix));
}

function formatStars(count) {
  if (count >= 1000) {
    return `${(count / 1000).toFixed(count >= 10000 ? 0 : 1)}k stars`;
  }

  return `${count} stars`;
}

function useReleaseFallback(message) {
  downloadButton.href = releasesURL;
  downloadButton.textContent = "Get Octowatch";
  downloadCardLink.href = releasesURL;

  if (releaseStatus) {
    releaseStatus.textContent = message;
  }
}

function useRepoFallback() {
  repoStars.textContent = "Open source";
  starsLink.href = repoURL;
}

async function loadRepoInfo() {
  try {
    const response = await fetch(repoInfoURL, {
      headers: {
        Accept: "application/vnd.github+json"
      }
    });

    if (!response.ok) {
      throw new Error(`GitHub API returned ${response.status}`);
    }

    const repo = await response.json();
    repoStars.textContent = formatStars(repo.stargazers_count ?? 0);
  } catch (error) {
    useRepoFallback();
  }
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
      useReleaseFallback("");
      return;
    }

    const primaryAsset = dmg ?? zip;
    downloadButton.href = primaryAsset.browser_download_url;
    downloadButton.textContent = `Download ${release.tag_name}`;
    downloadCardLink.href = primaryAsset.browser_download_url;

    const parts = [`Latest release ${release.tag_name}`];
    if (dmg) {
      parts.push("DMG");
    }
    if (zip) {
      parts.push("ZIP");
    }

    if (releaseStatus) {
      releaseStatus.textContent = `${parts.join(" · ")} available now.`;
    }
  } catch (error) {
    useReleaseFallback("");
  }
}

loadRepoInfo();
loadLatestRelease();
