export async function fetcher(...args: [RequestInfo | URL, RequestInit?]) {
  const response = await fetch(...args);
  // Without this, a 403 (GitHub anonymous rate limit) would resolve with the
  // error JSON — SWR would treat it as success and never retry, silently
  // wiping the version. Throwing keeps the last good value (the build-time
  // fallbackData) and lets SWR retry.
  if (!response.ok) throw new Error(`fetch failed: ${response.status}`);
  return response.json();
}