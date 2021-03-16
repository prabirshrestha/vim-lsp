use crate::calc::add::add;

fn document_definition_same_file() {
    func1();
}

fn func1() {
    unimplemented!();
}

fn document_definition_different_file() {
    add(1, 2);
}
