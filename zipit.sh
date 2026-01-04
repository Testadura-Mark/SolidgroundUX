source ./target-root/usr/local/lib/testadura/version.sh

release="$SGND_PRODUCT-$SGND_VERSION"

echo "[INFO] Release: $release"

# --- Stage directory ----------------------------------------------------------
mkdir -p "./releases/$release"

# --- Stage clean copy ---------------------------------------------------------
rsync -a --delete \
  --exclude '.*' \
  --exclude '*.state' \
  --exclude '*.code-workspace' \
  ./ "./releases/$release/"

# --- Create zip ---------------------------------------------------------------
zip -r "./releases/${release}.zip" "./releases/$release"

echo "[INFO] Created ./releases/${release}.zip"

# -- Cleanup staged dir ----------------------------------------------------------
rm -rf "./releases/$release"
echo "[INFO] Cleanup staged dir ./releases/$release"

echo "[INFO] Available releases:"
ls -ltr ./releases/*.zip