import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Search the web for information using SearXNG",
  args: {
    query: tool.schema.string().describe("The search query"),
  },
  async execute(args) {
    try {
      if (!args.query) {
        return "Error: Query is required."
      }

      const url = new URL("https://searxng.cowlab.org/search")
      url.searchParams.append("q", args.query)
      url.searchParams.append("format", "json")

      const response = await fetch(url.toString(), {
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
      })
      
      if (!response.ok) {
        return `Error fetching from SearXNG: ${response.statusText}`
      }
      
      const data = await response.json()
      
      if (!data.results || data.results.length === 0) {
        return "No results found."
      }

      // Limit to top 5 results to save context
      const results = data.results.slice(0, 5).map((r: any) => {
        return `Title: ${r.title}\nURL: ${r.url}\nSnippet: ${r.content || r.snippet || ""}\n`
      }).join("\n---\n")

      return results
    } catch (error: any) {
      return `Error during websearch: ${error.message}`
    }
  },
})
