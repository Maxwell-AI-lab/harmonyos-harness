// SkillsRSI 自检用的“迁移产物”：实现 SkillsRSI 示例任务所描述的数字格式化行为。
//
// 这是为本仓库自检专门写的实现，依据是示例任务说明和它的 13 项行为检查
// （整数分组、前导零、小数零位、空输入、表达式、负数、以小数点开头、已格式化、
// 本地化分隔符、印度分组及其负数与分隔符组合），没有复制或改写 OpenCalc 的源码。
// 约束与示例任务一致：不 import、不依赖平台接口、只导出一个顶层函数。
// 说明：只识别 ASCII 数字（0-9）。

function escapeForPattern(symbol: string): string {
  return symbol.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function isNumberStart(code: number, decimal: string): boolean {
  const isDigit = code >= 48 && code <= 57;
  const isDecimal = decimal.length > 0 && code === decimal.charCodeAt(0);
  return isDigit || isDecimal;
}

// 把输入切成“数字串”和“单个其他字符”两种片段。
function tokenize(text: string, decimal: string): string[] {
  const mark = escapeForPattern(decimal);
  const pattern: RegExp = new RegExp('[0-9' + mark + ']+|[^0-9' + mark + ']', 'g');
  const found: RegExpMatchArray | null = text.match(pattern);
  const tokens: string[] = [];
  if (found !== null) {
    for (let i = 0; i < found.length; i++) {
      tokens.push(found[i]);
    }
  }
  return tokens;
}

// 从右往左每 first 位切一段，之后每 rest 位切一段，用 separator 连接。
// 第一段宽度是 3、之后是 3 就是国际分组；第一段 3、之后 2 就是印度分组。
function insertGrouping(digits: string, separator: string, first: number, rest: number): string {
  let right = digits.length;
  let span = first;
  let grouped = '';
  while (right > span) {
    right -= span;
    grouped = separator + digits.substring(right, right + span) + grouped;
    span = rest;
  }
  return digits.substring(0, right) + grouped;
}

function formatNumber(token: string, decimal: string, separator: string, indian: boolean): string {
  if (decimal.length > 0 && token.startsWith(decimal)) {
    return token;
  }
  const index = decimal.length > 0 ? token.indexOf(decimal) : -1;
  const integer = index < 0 ? token : token.substring(0, index);
  const tail = index < 0 ? '' : token.substring(index);
  // 印度分组固定用英文逗号，这是示例任务要求保留的上游行为。
  const grouped = indian ? insertGrouping(integer, ',', 3, 2) : insertGrouping(integer, separator, 3, 3);
  return grouped + tail;
}

export function formatOpenCalcNumber(text: string, decimalSeparatorSymbol: string, groupingSeparatorSymbol: string,
  indian: boolean): string {
  if (text.length === 0) {
    return '';
  }
  let stripped = text;
  if (groupingSeparatorSymbol.length > 0) {
    stripped = text.split(groupingSeparatorSymbol).join('');
  }
  const tokens: string[] = tokenize(stripped, decimalSeparatorSymbol);
  let output = '';
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    const isNumber = isNumberStart(token.charCodeAt(0), decimalSeparatorSymbol);
    output += isNumber ? formatNumber(token, decimalSeparatorSymbol, groupingSeparatorSymbol, indian) : token;
  }
  return output;
}
