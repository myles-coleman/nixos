import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Search the web for information using SearXNG",
  args: {
    query: tool.schema.string().describe("The search query"),
  },
  async execute(args) {
    try {
      const url = `https://searxng.cowlab.org/search?q=${encodeURIComponent(args.query)}&format=json`
      const response = await fetch(url)
      
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
