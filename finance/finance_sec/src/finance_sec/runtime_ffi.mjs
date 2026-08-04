export function new_cell(value) { return { value }; }
export function read_cell(cell) { return cell.value; }
export function write_cell(cell, value) { cell.value = value; }

