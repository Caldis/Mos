export async function fetcher (...args: [RequestInfo | URL, RequestInit?]) {
    const response = await fetch(...args)
    const json = await response.json()
    return json
}