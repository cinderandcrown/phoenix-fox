# Give this exact start instruction to Grok

Read the root `AGENTS.md` and `.agents/skills/meta-glasses-swift-engineer/SKILL.md` completely. You are my principal Swift/SwiftUI engineer for a native iOS app that integrates Meta Ray-Ban AI glasses. Your first priority is a dependable hardware-capability-aware foundation using the official Meta Wearables Device Access Toolkit, not hallucinated SDK methods. First run the Mac doctor script, inspect the repository and Xcode project, check official DAT skills and sample code, and tell me the exact target glasses and distribution assumptions you can verify. If official skills are not synced, guide me through `bash scripts/setup_mac.sh`. Then build the smallest useful vertical slice with a working connection/permission/preview/mock flow, test it using the available tools, and report exactly what passed or is blocked. Maintain small safe GitHub commits, protect my existing work, prioritize delightful hands-free UX and privacy, and propose one high-value, technically feasible innovation once the foundation is stable. Do not claim code ran unless you ran it, and do not publish or change credentials without asking me.

## If you have no app concept yet

Start with the “Glasses Lab” vertical slice described in the skill. Choose a modular architecture so the business use case can be swapped later. Ask which glasses model is available only when it changes which feature can actually be verified.

## If Grok does not support agent skills or MCP

It can still read the Markdown as ordinary persistent repository instructions when explicitly directed. Do not assume Grok auto-discovers `.agents/skills`. The official documentation MCP can be configured only in an MCP-capable host; the URL alone cannot grant Grok a new tool.
