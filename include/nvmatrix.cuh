/*
 * nvmatrix.h
 *
 *  Created on: 20-Jan-2009
 *      Author: Alex Krizhevsky (akrizhevsky@gmail.com)
 */

#ifndef NVMATRIX_H_
#define NVMATRIX_H_

//#define RND_MULTIPLIERS_FILE ("rnd_multipliers_32bit.txt")

#ifndef RND_MULTIPLIERS_FILE
#define RND_MULTIPLIERS_FILE ("rnd_multipliers_32bit.txt")
#endif

#include <cublas.h>
#include <cuda.h>
#include <curand.h>
#include <cutil_inline.h>
#include <time.h>
#include <curand_kernel.h>

#include <matrix.h>
#include "../include/nvmatrix_kernel.cuh"

#ifdef WARNINGS
#define WARN(msg) printf("WARN: File %s, line %d: %s\n", __FILE__, __LINE__, msg);
#else
#define WARN(msg) ;
#endif

#define CUDA_CALL(x) do { if((x) != cudaSuccess) { \
                            printf("Error at %s:%d\n",__FILE__,__LINE__);\
                            exit(EXIT_FAILURE);}} while(0)
#define CURAND_CALL(x) do { if((x) != CURAND_STATUS_SUCCESS) { \
                            printf("Error at %s:%d\n",__FILE__,__LINE__);\
                            exit(EXIT_FAILURE);}} while(0)

class NVMatrix {
private:
    int _numCols, _numRows;
    int _numElements;
    int _stride;
    float* _devData;
    bool _isTrans;
    bool _ownsData;

//    static unsigned int hostRndMults[NUM_RND_STREAMS];
    static bool rndInitialized;
//    static unsigned int *devRndMults;
//    static unsigned long long *devRndWords;
    static curandGenerator_t rndGen;
    static curandState *rndDevStates;

    static void checkCublasError(const char* msg) {
        cublasStatus status = cublasGetError();
        if (status != CUBLAS_STATUS_SUCCESS) {
            fprintf(stderr, msg, NULL);
            exit(EXIT_FAILURE);
        }
    }

    char getTransChar() const {
        /*
         * not a typo! return opposite character because a
         * non-transposed krizhevsky matrix is in row-major order while a non-transposed
         * cublas matrix is in column-major order.
         */
        return _isTrans ? 'n' : 't';
    }

    unsigned int getNumRowsBackEnd() const {
        return _isTrans ? _numCols : _numRows;
    }

    void _init(int numRows, int numCols);
    void _init(int numRows, int numCols, int stride, bool isTrans);
    void _sum_setParams(int n, dim3* blocks, dim3* threads, int* numCols);
    template<class Agg> float _totalAgg(Agg agg);
    template<class Agg> void _aggregate(int axis, NVMatrix& target, Agg agg);
    template<class Agg> NVMatrix& _aggregate(int axis, Agg agg);
    template <class Randomizer> void _unaryRandomize(NVMatrix& target, Randomizer rnd);
    template <class Randomizer> void _binaryRandomize(NVMatrix& data2, NVMatrix& target, Randomizer rnd);
public:
    enum FUNCTIONS {LOG, LOGISTIC1, LOGISTIC2, EXP, SQUARE, SQRT, ZERO, ONE, RECIPROCAL, SIGN, ABS};
    NVMatrix();
    NVMatrix(bool isTrans);
    NVMatrix(int numRows, int numCols, bool isTrans=false);
    NVMatrix(const Matrix& like, bool copy);
    NVMatrix(const NVMatrix& like, bool copy);
    NVMatrix(const NVMatrix& like);
    NVMatrix(const Matrix& like);
    NVMatrix(float* devData, int numRows, int numCols, int stride, bool isTrans);
    ~NVMatrix();

    static void initRandom(unsigned long long seed);
    static void initRandom();
    static void destroyRandom();

    /*
     * DO NOT DEREFERENCE IN HOST CODE! This is a device memory pointer.
     */
    float* getCellPtr(int i, int j) const {
        if (_isTrans) {
            return &_devData[j * _numRows + i];
        }
        return &_devData[i * _numCols + j];
    }

    bool isSameDims(const Matrix& m) const {
        return m.getNumRows() == _numRows && m.getNumCols() == _numCols;
    }

    bool isSameDims(const NVMatrix& m) const {
        return m.getNumRows() == _numRows && m.getNumCols() == _numCols;
    }

    int getNumRows() const {
        return _numRows;
    }

    int getNumCols() const {
        return _numCols;
    }

    int getStride() const {
        return _stride;
    }

    int getLeadingDim() const {
        return _isTrans ? _numRows : _numCols;
    }

    int getFollowingDim() const {
        return !_isTrans ? _numRows : _numCols;
    }

    /*
     * FALSE:    Row-major order.
     * TRUE:     Column-major order.
     */
    bool isTrans() const {
        return _isTrans;
    }

    bool isView() const {
        return !_ownsData;
    }

    float* getDevData() const {
        return _devData;
    }

    unsigned int getNumElements() const {
        return _numElements;
    }

    /*
     * Only use if you know what you're doing!
     * Does not actually transpose matrix.
     */
    void setTrans(bool trans) {
        if (trans != _isTrans) {
            assert(isContiguous());
            _isTrans = trans;
            _stride = getLeadingDim();
        }
    }
    
    /*
     * Only use if you know what you're doing!
     * This toggles whether this object will free its GPU memory when it's destroyed.
     */
    void setView(bool isView) {
        _ownsData = !isView;
    }

    bool isContiguous() const {
        return _stride == getLeadingDim() || getFollowingDim() == 1;
    }
    
    void truncate() {
        resize(0,0);
    }

    void copyFromHost(const Matrix& hostMatrix);
    void copyFromHost(const Matrix& hostMatrix, bool resizeDeviceMatrix);
    void copyToHost(Matrix& hostMatrix) const;
    void copyToHost(Matrix& hostMatrix, bool resizeTarget) const;
    void copy(NVMatrix& dest) const;
    NVMatrix& copy() const;
    void addProduct(const NVMatrix& a, const NVMatrix &b, float scaleThis, float scaleAB);
    void addProduct(const NVMatrix& a, const NVMatrix &b);
    void rightMult(const NVMatrix &b, float scaleAB, NVMatrix &target) const;
    void rightMult(const NVMatrix &b, NVMatrix &target) const;
    void rightMult(const NVMatrix &b, float scaleAB);
    void randomizeUniform();
    void addGaussianNoise(NVMatrix& stdevs, NVMatrix& target);
    void addGaussianNoise(float stdev, NVMatrix& target);
    void addGaussianNoise(NVMatrix& stdevs);
    void addGaussianNoise(float stdev);
    void addGaussianNoise();
    void randomizeGaussian();
    void randomizeGaussian(float stdev);
    void randomizeGaussian(float mean, float stdev);
    void randomizeGaussian(NVMatrix& stdevs);
    void randomizeGaussian(NVMatrix& stdevs, NVMatrix& target);
    void binarizeProbs();
    void binarizeProbs(NVMatrix& target);
    void smallerThanScalar(float scalar, NVMatrix& target);
    void smallerThanScalar(float scalar);
    void biggerThanScalar(float scalar, NVMatrix& target);
    void biggerThanScalar(float scalar);
    void inRangeInc(float lower, float upper);
    void inRangeInc(float lower, float upper, NVMatrix& target);
    void inRangeExc(float lower, float upper);
    void inRangeExc(float lower, float upper, NVMatrix& target);

    void biggerThan(NVMatrix& m, NVMatrix& target);
    void biggerThan(NVMatrix& m);
    void biggerThanVector(NVMatrix& vec, NVMatrix& target);
    void biggerThanVector(NVMatrix& vec);
    void equals(NVMatrix& m, NVMatrix& target);
    void equals(NVMatrix& m);

    void _checkBounds(int startRow, int endRow, int startCol, int endCol) const;
    NVMatrix& slice(int startRow, int endRow, int startCol, int endCol) const;
    void slice(int startRow, int endRow, int startCol, int endCol, NVMatrix& target) const;
    NVMatrix& sliceRows(int startRow, int endRow) const;
    void sliceRows(int startRow, int endRow, NVMatrix& target) const;
    NVMatrix& sliceCols(int startCol, int endCol) const;
    void sliceCols(int startCol, int endCol, NVMatrix& target) const;

    void apply(NVMatrix::FUNCTIONS f, NVMatrix& target);
    void apply(NVMatrix::FUNCTIONS f);

    bool resize(int numRows, int numCols);
    bool resize(const NVMatrix &like);
    bool resize(const Matrix &like);
    void reshape(int numRows, int numCols);
    NVMatrix& reshaped(int numRows, int numCols);

    void copy(NVMatrix &dest, int srcStartRow, int srcEndRow, int srcStartCol, int srcEndCol,
                        int destStartRow, int destStartCol) const;

    void add(NVMatrix& b, float scaleA, float scaleB, NVMatrix& target);
    void add(NVMatrix& b, float scaleB, NVMatrix& target);
    void add(NVMatrix& b, NVMatrix& target);
    void add(NVMatrix& b, float scaleB);
    void add(NVMatrix& b, float scaleA, float scaleB);
    void add(NVMatrix& b);
    void addScalar(float scaleThis, float scalar, NVMatrix& target);
    void addScalar(float scalar, NVMatrix& target);
    void addScalar(float scalar);
    void subtractFromScalar(float scalar);
    void subtractFromScalar(float scalar, NVMatrix& target);
    void pow(float p);
    void pow(float p, NVMatrix& target);
    void eltwiseMult(NVMatrix& b);
    void eltwiseMult(NVMatrix& b, NVMatrix& target);
    void eltwiseDivide(NVMatrix& b);
    void eltwiseDivide(NVMatrix& b, NVMatrix& target);
    void squaredDiff(NVMatrix& b);
    void squaredDiff(NVMatrix& b, NVMatrix& target);
    void subtract(NVMatrix& b, NVMatrix& target);
    void subtract(NVMatrix& b);
    void addVector(NVMatrix& vec, float scaleVec, NVMatrix& target);
    void addVector(NVMatrix& vec);
    void addVector(NVMatrix& vec, float scaleVec);
    void addVector(NVMatrix& vec, NVMatrix& target);
    void equalsVector(NVMatrix& vec, NVMatrix& target);
    void equalsVector(NVMatrix& vec);
    void eltwiseMultByVector(NVMatrix& vec, NVMatrix& target);
    void eltwiseMultByVector(NVMatrix& vec);
    void eltwiseDivideByVector(NVMatrix& vec, NVMatrix& target);
    void eltwiseDivideByVector(NVMatrix& vec);
    void tile(int timesY, int timesX, NVMatrix& target);
    void scale(float _scale);
    void scale(float _scale, NVMatrix& target);
    void minWithScalar(float scalar, NVMatrix& target);
    void minWithScalar(float scalar);
    void maxWithScalar(float scalar, NVMatrix& target);
    void maxWithScalar(float scalar);

    void sum(int axis, NVMatrix& target);
    NVMatrix& sum(int axis);
    void max(int axis, NVMatrix& target);
    NVMatrix& max(int axis);
    void min(int axis, NVMatrix& target);
    NVMatrix& min(int axis);
    float sum();
    float max();
    float min();
    float norm2();
    float norm();

    float dotProduct(NVMatrix& b);

    /*
     * Does SOFT transpose and returns result, leaving this matrix unchanged
     */
    NVMatrix& getTranspose();

    /*
     * Does HARD transpose and puts result in target
     */
    void transpose(NVMatrix& target);

    /*
     * Does SOFT transpose
     */
    void transpose();
    bool transpose(bool trans);

    void flipTrans(NVMatrix& target);
    NVMatrix& flipTrans();

    void print(int startRow, int rows, int startCol, int cols) const;
    void print(int rows, int cols) const;
    void printShape(const char* name) const;


    template <class Op>
    void _eltwiseBinaryOp(NVMatrix& b, Op op) {
        _eltwiseBinaryOp<Op>(b, *this, op);
    }

    template <class Op>
    void _eltwiseBinaryOp(NVMatrix& b, NVMatrix& target, Op op) {
        assert(this->isSameDims(b));

        if (!target.isSameDims(*this)) {
            target.resize(*this);
        }

        int height = target.getFollowingDim(), width = target.getLeadingDim();
        dim3 blocks(std::min(NUM_BLOCKS_MAX, DIVUP(width, ELTWISE_THREADS_X)),
                    std::min(NUM_BLOCKS_MAX, DIVUP(height, ELTWISE_THREADS_Y)));
        dim3 threads(ELTWISE_THREADS_X, ELTWISE_THREADS_Y);
        if (target.isTrans() == isTrans() && target.isTrans() == b.isTrans()) {
            kEltwiseBinaryOp<Op><<<blocks, threads>>>(_devData, b._devData, target._devData, height, width, getStride(),
                                      b.getStride(), target.getStride(), op);
            cutilCheckMsg("kEltwiseOp: Kernel execution failed");
        } else {
            //  both x here since y divides x
            bool checkBounds = !(width % ELTWISE_THREADS_X == 0 && height % ELTWISE_THREADS_X == 0);
            if (target.isTrans() == isTrans() && target.isTrans() != b.isTrans()) {
                if (checkBounds) {
                    kEltwiseBinaryOpTrans<Op,true,false,false><<<blocks, threads>>>(_devData, b._devData, target._devData, height, width,getStride(),
                                                               b.getStride(), target.getStride(), op);
                } else {
                    kEltwiseBinaryOpTrans<Op,false,false,false><<<blocks, threads>>>(_devData, b._devData, target._devData, height, width,getStride(),
                                                               b.getStride(), target.getStride(), op);
                }
            } else if (target.isTrans() != isTrans() && target.isTrans() != b.isTrans()) {
                if (checkBounds) {
                    kEltwiseBinaryOpTrans<Op,true,true,false><<<blocks, threads>>>(_devData, b._devData, target._devData, height, width,getStride(),
                                                               b.getStride(), target.getStride(), op);
                } else {
                    kEltwiseBinaryOpTrans<Op,false,true,false><<<blocks, threads>>>(_devData, b._devData, target._devData, height, width,getStride(),
                                                               b.getStride(), target.getStride(), op);
                }
            } else if (target.isTrans() != isTrans() && target.isTrans() == b.isTrans()) {
                if (checkBounds) {
                    kEltwiseBinaryOpTrans<Op,true,false,true><<<blocks, threads>>>(b._devData, _devData, target._devData, height, width,b.getStride(),
                                                               getStride(), target.getStride(), op);
                } else {
                    kEltwiseBinaryOpTrans<Op,false,false,true><<<blocks, threads>>>(b._devData, _devData, target._devData, height, width, b.getStride(),
                                                               getStride(), target.getStride(), op);
                }
            }
            cutilCheckMsg("kEltwiseOpTrans: Kernel execution failed");
        }
    }
    /*
     * __global__ void kEltwiseUnaryOp(float* a, float* dest, const uint numRows, const uint numCols,
                                    const uint strideA, const uint strideDest, Op op) {
     */
    template <class Op>
    void _eltwiseUnaryOp(NVMatrix& target, Op op) {
        if (!target.isSameDims(*this)) {
            target.resize(*this);
        }
        int height = target.getFollowingDim(), width = target.getLeadingDim();
        dim3 blocks(std::min(NUM_BLOCKS_MAX, DIVUP(width, ELTWISE_THREADS_X)),
                std::min(NUM_BLOCKS_MAX, DIVUP(height, ELTWISE_THREADS_Y)));
        dim3 threads(ELTWISE_THREADS_X, ELTWISE_THREADS_Y);
        if (target.isTrans() == isTrans()) {
            kEltwiseUnaryOp<Op><<<blocks, threads>>>(_devData, target._devData, height, width, getStride(), target.getStride(), op);
            cutilCheckMsg("kEltwiseUnaryOp: Kernel execution failed");
        } else {
            bool checkBounds = !(width % ELTWISE_THREADS_X == 0 && height % ELTWISE_THREADS_X == 0);
            if (checkBounds) {
                kEltwiseUnaryOpTrans<Op, true><<<blocks, threads>>>(_devData, target._devData, height, width, getStride(), target.getStride(), op);
            } else {
                kEltwiseUnaryOpTrans<Op, false><<<blocks, threads>>>(_devData, target._devData, height, width, getStride(), target.getStride(), op);
            }
            cutilCheckMsg("kEltwiseUnaryOpTrans: Kernel execution failed");
        }
    }

    template <class Op>
    void _eltwiseUnaryOp( Op op) {
        _eltwiseUnaryOp<Op>(*this, op);
    }

    template <class Op>
    void _eltwiseVectorOp(NVMatrix& vec, NVMatrix& target, Op op) {
        assert(&target != &vec); // for now
        assert(vec.getNumRows() == 1 || vec.getNumCols() == 1);
        assert(vec.getNumRows() == _numRows || vec.getNumCols() == _numCols);
        assert(vec.isContiguous());

        target.resize(*this); // target must be same orientation as me for now

        int width = getLeadingDim(); //_isTrans ? _numRows : _numCols;
        int height = getFollowingDim(); //_isTrans ? _numCols : _numRows;
        dim3 threads(ADD_VEC_THREADS_X, ADD_VEC_THREADS_Y);
        dim3 blocks(MIN(NUM_BLOCKS_MAX, DIVUP(width, ADD_VEC_THREADS_X)), MIN(NUM_BLOCKS_MAX, DIVUP(height, ADD_VEC_THREADS_Y)));
        if (vec.getNumRows() == _numRows && !isTrans() || vec.getNumCols() == _numCols && isTrans()) {
            kColVectorOp<Op><<<blocks,threads>>>(_devData, vec._devData, target._devData, width, height, getStride(), target.getStride(), op);
        } else {
            kRowVectorOp<Op><<<blocks,threads>>>(_devData, vec._devData, target._devData, width, height, getStride(), target.getStride(), op);
        }
        cutilCheckMsg("Kernel execution failed");
    //    cudaThreadSynchronize();
    }

    template<class UnaryOperator> float argMax(UnaryOperator u) {
       return _totalAgg<ArgMaxAggregator<UnaryOperator> >(ArgMaxAggregator<UnaryOperator>(u));
    }

};

#endif /* NVMATRIX_H_ */
