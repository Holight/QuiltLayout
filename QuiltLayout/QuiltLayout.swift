//
//  QuiltLayout.swift
//  QuiltLayout
//

import Foundation
import UIKit

@objc protocol QuiltLayoutDelegate: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize // defaults to 1x1
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets // defaults to uiedgeinsetszero
}

class QuiltLayout: UICollectionViewLayout {
    var delegate: QuiltLayoutDelegate?
    var blockPixels: CGSize = CGSize(width: 100, height: 100) { // defaults to 100x100
        didSet {
            invalidateLayout()
        }
    }
    var direction: UICollectionViewScrollDirection = .vertical { // defaults to vertical
        didSet {
            invalidateLayout()
        }
    }
    
    // only use this if you don't have more than 1000ish items.
    // this will give you the correct size from the start and
    // improve scrolling speed, at the cost of time at the beginning
    var prelayoutEverything = false
    
    private var firstOpenSpace = CGPoint()
    private var furthestBlockPoint = CGPoint()
    
    func setFurthestBlockPoint(point: CGPoint) {
        self.furthestBlockPoint = CGPoint(x: max(self.furthestBlockPoint.x, point.x), y: max(self.furthestBlockPoint.y, point.y))
    }
    
    // this will be a 2x2 dictionary storing nsindexpaths
    // which indicate the available/filled spaces in our quilt
    var indexPathByPosition = [CGFloat : [CGFloat : IndexPath]]()
    
    // indexed by "section, row" this will serve as the rapid
    // lookup of block position by indexpath.
    var positionByIndexPath = [Int : [Int : CGPoint]]()
    
    var hasPositionsCached: Bool?
    
    // previous layout cache.  this is to prevent choppiness
    // when we scroll to the bottom of the screen - uicollectionview
    // will repeatedly call layoutattributesforelementinrect on
    // each scroll event.  pow!
    var previousLayoutAttributes: [UICollectionViewLayoutAttributes]?
    var previousLayoutRect: CGRect?
    
    // remember the last indexpath placed, as to not
    // relayout the same indexpaths while scrolling
    var lastIndexPathPlaced: IndexPath?

    override var collectionViewContentSize: CGSize {
        let isVert = self.direction == .vertical;
    
        let contentRect = UIEdgeInsetsInsetRect(self.collectionView!.frame, self.collectionView!.contentInset);
        if (isVert) {
            return CGSize(width: contentRect.width, height: (self.furthestBlockPoint.y+1) * self.blockPixels.height)
        }
        else {
            return CGSize(width: (self.furthestBlockPoint.x+1) * self.blockPixels.width, height: contentRect.height)
        }
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        if (self.delegate == nil) {
            return nil
        }
        
        // see the comment on these properties
        if(rect == self.previousLayoutRect) {
            return self.previousLayoutAttributes
        }
        self.previousLayoutRect = rect
        
        let isVert = (self.direction == .vertical)
        
        let unrestrictedDimensionStart = Int(isVert ? rect.origin.y / self.blockPixels.height : rect.origin.x / self.blockPixels.width)
        let unrestrictedDimensionLength = Int((isVert ? rect.size.height / self.blockPixels.height : rect.size.width / self.blockPixels.width) + 1)
        let unrestrictedDimensionEnd = unrestrictedDimensionStart + unrestrictedDimensionLength
        
        self.fillInBlocks(toUnrestricted: self.prelayoutEverything ? Int.max : unrestrictedDimensionEnd)
        
        // find the indexPaths between those rows
        var attributes = Set<UICollectionViewLayoutAttributes>()
        _ = self.traverseTilesBetweenUnrestrictedDimension(begin: unrestrictedDimensionStart, and: unrestrictedDimensionEnd) { point in
            if let indexPath = self.indexPath(for: point) {
                if let attribute = self.layoutAttributesForItem(at: indexPath) {
                    attributes.insert(attribute)
                }
            }
            
            return true
        }
        
        self.previousLayoutAttributes = Array(attributes)
        return self.previousLayoutAttributes
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let insets = self.delegate?.collectionView(self.collectionView!, layout: self, insetForSectionAt: indexPath.item)
        let frame = self.frame(for: indexPath)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = UIEdgeInsetsInsetRect(frame, insets ?? UIEdgeInsets())
        return attributes
    }
    
    func shouldInvalidateLayoutForBoundsChange(newBounds: CGRect) -> Bool {
        return newBounds.size == self.collectionView!.frame.size
    }
    
    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        
        for item in updateItems {
            if (item.updateAction == .insert || item.updateAction == .move) {
                self.fillInBlocks(to: item.indexPathAfterUpdate!)
            }
        }
    }
    
    override func invalidateLayout() {
        super.invalidateLayout()
        
        self.furthestBlockPoint = CGPoint.zero
        self.firstOpenSpace = CGPoint.zero
        self.previousLayoutRect = CGRect.zero
        self.previousLayoutAttributes = nil
        self.lastIndexPathPlaced = nil
        self.clearPositions()
    }
    
    override func prepare() {
        super.prepare()
        
        if (self.delegate == nil) { return }
        
        let isVert = self.direction == .vertical
        
        let scrollFrame = CGRect(x: self.collectionView!.contentOffset.x, y: self.collectionView!.contentOffset.y, width: self.collectionView!.frame.size.width, height: self.collectionView!.frame.size.height)
        
        var unrestrictedRow = 0
        if (isVert) {
            unrestrictedRow = Int(scrollFrame.maxY / self.blockPixels.height) + 1
        }
        else {
            unrestrictedRow = Int(scrollFrame.maxX / self.blockPixels.width) + 1
        }
        self.fillInBlocks(toUnrestricted: self.prelayoutEverything ? Int.max : unrestrictedRow)
    }

    func fillInBlocks(toUnrestricted endRow: Int) {
        let vert = (self.direction == .vertical)
        
        // we'll have our data structure as if we're planning
        // a vertical layout, then when we assign positions to
        // the items we'll invert the axis
        
        let numSections = self.collectionView!.numberOfSections
        for section in (self.lastIndexPathPlaced?.section ?? 0)..<numSections {
            let numRows = self.collectionView!.numberOfItems(inSection: section)
            for row in ((self.lastIndexPathPlaced?.row ?? -1) + 1)..<numRows {
                let indexPath = IndexPath(row: row, section: section)
                
                if (self.placeBlock(at: indexPath)) {
                    self.lastIndexPathPlaced = indexPath
                }
                
                // only jump out if we've already filled up every space up till the resticted row
                if ((vert ? self.firstOpenSpace.y : self.firstOpenSpace.x) >= CGFloat(endRow)) {
                    return
                }
            }
        }
    }
    
    func fillInBlocks(to path: IndexPath) {
        // we'll have our data structure as if we're planning
        // a vertical layout, then when we assign positions to
        // the items we'll invert the axis
        
        let numSections = self.collectionView!.numberOfSections
        for section in (self.lastIndexPathPlaced?.section ?? 0)..<numSections {
            let numRows = self.collectionView!.numberOfItems(inSection: section)
            for row in ((self.lastIndexPathPlaced?.row ?? -1) + 1)..<numRows {
                
                // exit when we are past the desired row
                if (section >= path.section && row > path.row) { return }
                
                let indexPath = IndexPath(row: row, section: section)
                
                if (self.placeBlock(at: indexPath)) {
                    self.lastIndexPathPlaced = indexPath
                }
            }
        }
    }
    
    func placeBlock(at indexPath: IndexPath) -> Bool {
        let blockSize = self.getBlockSizeForItem(at: indexPath)
        let vert = self.direction == .vertical
        
        return !self.traverseOpenTiles() { blockOrigin in
            
            // we need to make sure each square in the desired
            // area is available before we can place the square
            
            let didTraverseAllBlocks = self.traverseTilesForPoint(point: blockOrigin, with: blockSize) { point in
                let spaceAvailable = self.indexPath(for: point) == nil
                let inBounds = (vert ? point.x : point.y) < CGFloat(self.restrictedDimensionBlockSize)
                let maximumRestrictedBoundSize = (vert ? blockOrigin.x : blockOrigin.y) == 0
                
                if (spaceAvailable && maximumRestrictedBoundSize && !inBounds) {
                    NSLog("\(type(of: self)): layout is not \(vert ? "wide" : "tall") enough for this piece size: \(blockSize)! Adding anyway...");
                    return true
                }
            
                return spaceAvailable && inBounds
            }
            
            if (!didTraverseAllBlocks) { return true }
            
            // because we have determined that the space is all
            // available, lets fill it in as taken.
        
            self.setIndexPath(path: indexPath, for: blockOrigin)
            
            _ = self.traverseTilesForPoint(point: blockOrigin, with: blockSize) { point in
                self.setPosition(point: point, for: indexPath)
                
                self.setFurthestBlockPoint(point: point)
                
                return true
            }
            
            return false
        }
    }
    
    func traverseTilesBetweenUnrestrictedDimension(begin: Int, and end: Int, iterator block: (CGPoint) -> Bool) ->Bool {
        let isVert = self.direction == .vertical
        
        // the double ;; is deliberate, the unrestricted dimension should iterate indefinitely
        for unrestrictedDimension in begin..<end {
            for restrictedDimension in 0..<self.restrictedDimensionBlockSize {
                let point = CGPoint(x: isVert ? restrictedDimension : unrestrictedDimension, y: isVert ? unrestrictedDimension : restrictedDimension)
                
                if (!block(point)) {
                    return false
                }
            }
        }
        
        return true
    }
    
    func traverseTilesForPoint(point: CGPoint, with size: CGSize, iterator block: (CGPoint) -> Bool) ->Bool {
        var col = point.x
        while col < point.x + size.width {
            var row = point.y
            while row < point.y + size.height {
                if (!block(CGPoint(x: col, y: row))) {
                    return false
                }
                row += 1
            }
            col += 1
        }
        
        return true;
    }
    
    func traverseOpenTiles(block: (CGPoint) -> Bool) ->Bool {
        var allTakenBefore = true
        let isVert = self.direction == .vertical
        
        // the while true is deliberate, the unrestricted dimension should iterate indefinitely
        var unrestrictedDimension = isVert ? self.firstOpenSpace.y : self.firstOpenSpace.x
        while true {
            for restrictedDimension in 0..<self.restrictedDimensionBlockSize {
                let point = CGPoint(x: isVert ? CGFloat(restrictedDimension) : unrestrictedDimension,
                                    y: isVert ? unrestrictedDimension : CGFloat(restrictedDimension))
                
                if (self.indexPath(for: point) != nil) {
                    continue
                }
                
                if (allTakenBefore) {
                    self.firstOpenSpace = point
                    allTakenBefore = false
                }
                
                if (!block(point)) {
                    return false
                }
            }
            
            unrestrictedDimension += 1
        }
        
        assert(false, "Could find no good place for a block!")
        return true
    }
    
    func clearPositions() {
        self.indexPathByPosition.removeAll()
        self.positionByIndexPath.removeAll()
    }
    
    func indexPath(for point: CGPoint) -> IndexPath? {
        let isVert = self.direction == .vertical
        
        // to avoid creating unbounded nsmutabledictionaries we should
        // have the innerdict be the unrestricted dimension
    
        let unrestrictedPoint = (isVert ? point.y : point.x)
        let restrictedPoint = (isVert ? point.x : point.y)
        
        return self.indexPathByPosition[restrictedPoint]?[unrestrictedPoint]
    }
    
    func setPosition(point: CGPoint, for indexPath: IndexPath) {
        let isVert = self.direction == .vertical
        
        // to avoid creating unbounded nsmutabledictionaries we should
        // have the innerdict be the unrestricted dimension
        
        let unrestrictedPoint = (isVert ? point.y : point.x)
        let restrictedPoint = (isVert ? point.x : point.y)
        
        if self.indexPathByPosition[restrictedPoint] == nil {
            self.indexPathByPosition[restrictedPoint] = [CGFloat : IndexPath]()
        }
        
        self.indexPathByPosition[restrictedPoint]![unrestrictedPoint] = indexPath
    }
    
    func position(for path: IndexPath) -> CGPoint {
        
        // if item does not have a position, we will make one!
        if self.positionByIndexPath[path.section]![path.row] == nil {
            self.fillInBlocks(to: path)
        }
        
        return self.positionByIndexPath[path.section]![path.row]!
    }
    
    func setIndexPath(path: IndexPath, for point: CGPoint) {
        if self.positionByIndexPath[path.section] == nil {
            self.positionByIndexPath[path.section] = [Int : CGPoint]()
        }
        
        self.positionByIndexPath[path.section]![path.row] = point
    }
    
    func frame(for path: IndexPath) -> CGRect {
        let isVert = self.direction == .vertical
        let position = self.position(for: path)
        let elementSize = self.getBlockSizeForItem(at: path)
        
        let contentRect = UIEdgeInsetsInsetRect(self.collectionView!.frame, self.collectionView!.contentInset)
        if (isVert) {
            let initialPaddingForContraintedDimension = (contentRect.width - CGFloat(self.restrictedDimensionBlockSize) * self.blockPixels.width) / 2
            return CGRect(x: position.x*self.blockPixels.width + initialPaddingForContraintedDimension,
                          y: position.y*self.blockPixels.height,
                          width: elementSize.width*self.blockPixels.width,
                          height: elementSize.height*self.blockPixels.height)
        }
        else {
            let initialPaddingForContraintedDimension = (contentRect.height - CGFloat(self.restrictedDimensionBlockSize) * self.blockPixels.height) / 2
            return CGRect(x: position.x*self.blockPixels.width,
                          y: position.y*self.blockPixels.height + initialPaddingForContraintedDimension,
                          width: elementSize.width*self.blockPixels.width,
                          height: elementSize.height*self.blockPixels.height)
        }
    }
    
    //This method is prefixed with get because it may return its value indirectly
    func getBlockSizeForItem(at indexPath: IndexPath) -> CGSize {
        let blockSize = self.delegate?.collectionView(self.collectionView!, layout: self, sizeForItemAt: indexPath)
        return blockSize ?? CGSize(width: 1, height: 1)
    }
    
    override func targetIndexPath(forInteractivelyMovingItem previousIndexPath: IndexPath, withPosition position: CGPoint) -> IndexPath {
        let point = CGPoint(x: Int(position.x / blockPixels.width), y: Int(position.y / blockPixels.height))
        return indexPath(for: point) ?? super.targetIndexPath(forInteractivelyMovingItem: previousIndexPath, withPosition: position)
    }
    
    private var didShowMessage = false
    
    // this will return the maximum width or height the quilt
    // layout can take, depending on we're growing horizontally
    // or vertically
    var restrictedDimensionBlockSize: Int {
        let isVert = self.direction == .vertical
        
        let contentRect = UIEdgeInsetsInsetRect(self.collectionView!.frame, self.collectionView!.contentInset)
        let size = Int(isVert ? contentRect.width / self.blockPixels.width : contentRect.height / self.blockPixels.height)
        
        if (size == 0) {
            if(!didShowMessage) {
                NSLog("\(type(of: self)): cannot fit block of size: \(self.blockPixels) in content rect \(contentRect)!  Defaulting to 1");
                didShowMessage = true;
            }
            return 1
        }
        
        return size
    }
}
