"use strict";
const fs = require("node:fs/promises"),
  path = require("node:path");
const { emptyState, validateState } = require("./core.cjs");
class Store {
  constructor(directory) {
    this.directory = directory;
    this.tail = Promise.resolve();
  }
  async read(name) {
    try {
      return JSON.parse(
        await fs.readFile(path.join(this.directory, name), "utf8"),
      );
    } catch (e) {
      if (e.code === "ENOENT") return null;
      throw e;
    }
  }
  async load() {
    return validateState((await this.read("workspace.json")) || emptyState());
  }
  write(name, value) {
    const job = this.tail
      .catch(() => {})
      .then(async () => {
        await fs.mkdir(this.directory, { recursive: true });
        const target = path.join(this.directory, name),
          temp = target + ".tmp";
        await fs.writeFile(temp, JSON.stringify(value));
        await fs.rename(temp, target);
      });
    this.tail = job;
    return job;
  }
  async save(value) {
    validateState(value);
    return this.write("workspace.json", value);
  }
}
module.exports = { Store };
