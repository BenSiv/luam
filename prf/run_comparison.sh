#!/bin/bash
# Benchmark Comparison Script
# Compares performance between Odin implementation (current) and C implementation (main branch)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."

echo -e "${BLUE}=== LuaM Benchmark Comparison ===${NC}"
echo ""

# Step 1: Build Odin implementation (current branch)
echo -e "${YELLOW}Step 1: Ensuring Odin implementation is built...${NC}"
cd "$PROJECT_ROOT"
CURRENT_BRANCH=$(git branch --show-current)
echo "Current branch: $CURRENT_BRANCH"

if [ ! -f "bin/luam_odin" ]; then
    echo "Building Odin implementation..."
    ./bld/build.sh
else
    echo "Odin executable found: bin/luam_odin"
fi

# Step 2: Build C implementation from main branch
echo ""
echo -e "${YELLOW}Step 2: Building C implementation from main branch...${NC}"

# Create a temporary directory for the main branch build
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Clone or copy the main branch
cd "$TEMP_DIR"
git clone "$PROJECT_ROOT" luam_main
cd luam_main
git checkout main

# Build the C implementation
echo "Building C implementation..."
cd src
make clean > /dev/null 2>&1
make linux MYCFLAGS="-DLUA_USE_LINUX" > /dev/null 2>&1
cd ..

# Copy the lua executable to a known location
mkdir -p "$PROJECT_ROOT/prf/bin"
cp "$TEMP_DIR/luam_main/src/lua" "$PROJECT_ROOT/prf/bin/luam_c"
chmod +x "$PROJECT_ROOT/prf/bin/luam_c"

echo -e "${GREEN}C implementation built: prf/bin/luam_c${NC}"

# Step 3: Run benchmarks
echo ""
echo -e "${YELLOW}Step 3: Running benchmarks...${NC}"
cd "$PROJECT_ROOT/prf"

# Create results directory
RESULTS_DIR="results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo ""
echo -e "${BLUE}--- Running Odin Implementation Benchmarks ---${NC}"
"$PROJECT_ROOT/bin/luam_odin" bench_luam.lua | tee "$RESULTS_DIR/odin_results.txt"

echo ""
echo -e "${BLUE}--- Running C Implementation Benchmarks ---${NC}"
"$PROJECT_ROOT/prf/bin/luam_c" bench_lua51.lua | tee "$RESULTS_DIR/c_results.txt"

# Step 4: Generate comparison report
echo ""
echo -e "${YELLOW}Step 4: Generating comparison report...${NC}"

cat > "$RESULTS_DIR/comparison.md" << 'EOF'
# Benchmark Comparison Report

## Test Environment
- **Date**: $(date +"%Y-%m-%d %H:%M:%S")
- **Platform**: $(uname -s) $(uname -m)
- **Current Branch**: $CURRENT_BRANCH

---

## Results

### Odin Implementation (Current Branch)
\`\`\`
EOF

cat "$RESULTS_DIR/odin_results.txt" >> "$RESULTS_DIR/comparison.md"

cat >> "$RESULTS_DIR/comparison.md" << 'EOF'
\`\`\`

### C Implementation (Main Branch)
\`\`\`
EOF

cat "$RESULTS_DIR/c_results.txt" >> "$RESULTS_DIR/comparison.md"

cat >> "$RESULTS_DIR/comparison.md" << 'EOF'
\`\`\`

---

## Analysis

To be filled in manually or with additional analysis tools.

EOF

# Expand variables in the markdown file
DATE_NOW=$(date +"%Y-%m-%d %H:%M:%S")
PLATFORM_INFO="$(uname -s) $(uname -m)"
sed -i "s/\$(date +\"%Y-%m-%d %H:%M:%S\")/$DATE_NOW/" "$RESULTS_DIR/comparison.md"
sed -i "s/\$(uname -s) \$(uname -m)/$PLATFORM_INFO/" "$RESULTS_DIR/comparison.md"
sed -i "s/\$CURRENT_BRANCH/$CURRENT_BRANCH/" "$RESULTS_DIR/comparison.md"

echo -e "${GREEN}Comparison report saved to: $RESULTS_DIR/comparison.md${NC}"

# Step 5: Display side-by-side comparison
echo ""
echo -e "${BLUE}=== Side-by-Side Comparison ===${NC}"
echo ""
printf "%-30s | %-15s | %-15s\n" "Benchmark" "Odin (current)" "C (main)"
printf "%-30s-+-%-15s-+-%-15s\n" "------------------------------" "---------------" "---------------"

# Parse and display results
while IFS=: read -r bench_name time; do
    bench_name=$(echo "$bench_name" | xargs)
    time=$(echo "$time" | xargs)
    odin_times["$bench_name"]="$time"
done < <(grep -E "^[A-Za-z].*:" "$RESULTS_DIR/odin_results.txt" || true)

while IFS=: read -r bench_name time; do
    bench_name=$(echo "$bench_name" | xargs)
    time=$(echo "$time" | xargs)
    c_times["$bench_name"]="$time"
done < <(grep -E "^[A-Za-z].*:" "$RESULTS_DIR/c_results.txt" || true)

# Display comparison
for bench in "${!odin_times[@]}"; do
    printf "%-30s | %-15s | %-15s\n" "$bench" "${odin_times[$bench]}" "${c_times[$bench]:-N/A}"
done

# Cleanup
echo ""
echo -e "${YELLOW}Cleaning up temporary files...${NC}"
rm -rf "$TEMP_DIR"

echo ""
echo -e "${GREEN}=== Benchmark Comparison Complete ===${NC}"
echo -e "Results saved in: ${BLUE}prf/$RESULTS_DIR/${NC}"
echo ""
