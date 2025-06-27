// @ts-check
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import catppuccin from "@catppuccin/starlight";

// const isGithubPages = process.env.GITHUB_PAGES === "true";
const isGithubPages = false;

// https://astro.build/config
export default defineConfig({
  base: isGithubPages ? "/apt-archive/" : "/",
  integrations: [
    starlight({
      title: "Fuabioo's APT repository",
      logo: {
        src: "./src/assets/logo.svg"
      },
      pagefind: false,
      sidebar: [
        {
          label: "Home",
          link: "/"
        },
        {
          label: "Installation Guide",
          link: "/installation/"
        },
        {
          label: "Available Packages",
          link: "/packages/"
        },
        {
          label: "Testing & Development",
          link: "/testing/"
        },
        {
          label: "How It Works",
          link: "/how-it-works/"
        }
      ],
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/Fuabioo/apt-archive"
        }
      ],
      plugins: [
        catppuccin({
          dark: { flavor: "mocha" },
          light: { flavor: "latte" }
        })
      ]
    })
  ]
});
