import prettier from "eslint-plugin-prettier";
import globals from "globals";
import path from "node:path";
import { fileURLToPath } from "node:url";
import js from "@eslint/js";
import { FlatCompat } from "@eslint/eslintrc";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const compat = new FlatCompat({
    baseDirectory: __dirname,
    recommendedConfig: js.configs.recommended,
    allConfig: js.configs.all
});

export default [...compat.extends("eslint:recommended"), {
    plugins: {
        prettier,
    },

    languageOptions: {
        globals: {
            ...globals.node,
            ...globals.commonjs,
            ...globals.jest,
        },

        ecmaVersion: 2020,
        sourceType: "commonjs",
    },

    rules: {
        "prettier/prettier": "error",
        "linebreak-style": ["error", "unix"],
        semi: ["error", "always"],
        "no-console": "off",
    },
}];
