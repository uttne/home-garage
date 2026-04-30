import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import Handlebars from 'handlebars';

type TemplateContext = Record<string, string | number | boolean>;

const templatesRoot = resolve(__dirname, '..', 'templates');

export function renderTemplate(templateName: string, context: TemplateContext): string {
  const templatePath = resolve(templatesRoot, templateName);
  const source = readFileSync(templatePath, 'utf8');
  const template = Handlebars.compile(source, { noEscape: true });
  return `${template(context).trimEnd()}\n`;
}
