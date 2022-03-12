# Build and test
build :; CAIRO_PATH=openzeppelin nile compile
test  :; pytest tests/
