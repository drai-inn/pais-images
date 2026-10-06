// The PAIS gateway as pi's `pais` provider. Loaded by the /usr/local/bin/pi wrapper with `-e`, so it
// sits alongside the researcher's own extensions and ~/.pi/agent/models.json, which pi applies on
// top of it. Endpoint and model come from what the template injects (LLM_API_BASE, LLM_MODEL), the
// key from the researcher's Coder user secret (OPENAI_API_KEY).
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	const baseUrl = process.env.LLM_API_BASE;
	const model = process.env.LLM_MODEL;
	if (!baseUrl || !model) return;

	pi.registerProvider("pais", {
		name: "PAIS",
		baseUrl,
		apiKey: "$OPENAI_API_KEY",
		api: "openai-completions",
		models: [
			{
				id: model,
				name: model,
				// The gateway's model list carries no limits, and LLM_MODEL changes with the template, so
				// these are the smallest across the models PAIS serves rather than this model's own.
				// `reasoning: false` stops pi sending reasoning_effort, whose values differ per model
				// (DeepSeek V4.1 rejects pi's "medium"); the served models think by default regardless.
				reasoning: false,
				input: ["text"],
				contextWindow: 262144,
				maxTokens: 32768,
				cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
			},
		],
	});

	// OPENAI_API_KEY holds the PAIS gateway key, but it also enables pi's built-in `openai` provider,
	// which is pi's first choice of model when none is saved and which sends the key to
	// api.openai.com. Pointing that provider at the gateway keeps the key there, and a session that
	// starts on an `openai/*` model, none of which the gateway routes, moves to the PAIS model. That
	// switch is for the session only; the researcher's saved default is untouched.
	pi.registerProvider("openai", { baseUrl });
	pi.on("session_start", async (_event, ctx) => {
		const pais = ctx.modelRegistry.find("pais", model);
		if (ctx.model?.provider === "openai" && pais) await pi.setModel(pais);
	});
}
